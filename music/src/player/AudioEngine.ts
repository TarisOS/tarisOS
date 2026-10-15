// Modified for TarisOS (Taris Music) by George Dobreff ("Witcher") and contributors, 2026.
import { logInternalError, logInternalInfo, logInternalWarn } from "../internal/logging";
import type { RustAudioSource } from "../datasource/types";
import * as rustAudio from "./rustAudio";

type YouTubePlayerEvent = {
  data: number;
};

type YouTubePlayer = {
  /** Optional: present on the IFrame API, absent in older embeds. */
  setPlaybackRate?(rate: number): void;
  cueVideoById(videoId: string): void;
  loadVideoById(videoId: string): void;
  playVideo(): void;
  pauseVideo(): void;
  stopVideo(): void;
  seekTo(seconds: number, allowSeekAhead: boolean): void;
  setVolume(volume: number): void;
  getVolume(): number;
  mute(): void;
  unMute(): void;
  isMuted(): boolean;
  getCurrentTime(): number;
  getDuration(): number;
  getPlayerState(): number;
  getVideoData(): { video_id?: string };
  destroy(): void;
};

type YouTubePlayerConstructor = new (
  element: HTMLElement,
  options: {
    width: number;
    height: number;
    videoId?: string;
    playerVars: Record<string, number | string>;
    events: {
      onReady: () => void;
      onStateChange: (event: YouTubePlayerEvent) => void;
      onError: (event: YouTubePlayerEvent) => void;
    };
  },
) => YouTubePlayer;

declare global {
  interface Window {
    YT?: {
      Player: YouTubePlayerConstructor;
      PlayerState: {
        UNSTARTED: number;
        ENDED: number;
        PLAYING: number;
        PAUSED: number;
        CUED: number;
      };
    };
    onYouTubeIframeAPIReady?: () => void;
  }
}

let iframeApiPromise: Promise<void> | null = null;
let playbackClaimId = 0;
let playbackOwner: AudioEngine | null = null;

/*
 * One `ended` subscription for the whole process, dispatched to the engine that owns playback.
 * Installed on the first Rust load rather than at import.
 */
let rustEndedRouted = false;

function routeRustEnded(): void {
  if (rustEndedRouted) return;
  rustEndedRouted = true;
  rustAudio.setEndedListener(() => {
    playbackOwner?.handleRustEnded();
  });
}

function isPlayerStateTimeout(error: unknown): boolean {
  return error instanceof Error
    && /^Timed out waiting for YouTube player state: /.test(error.message);
}

function allowYouTubeIframePlayback(host: HTMLElement): void {
  const iframe = host.querySelector("iframe");
  if (!iframe) return;
  iframe.setAttribute("allow", "autoplay; encrypted-media; picture-in-picture");
}

function loadYouTubeIframeApi(): Promise<void> {
  if (window.YT?.Player) return Promise.resolve();
  if (iframeApiPromise) return iframeApiPromise;

  iframeApiPromise = new Promise((resolve, reject) => {
    const previousReady = window.onYouTubeIframeAPIReady;
    window.onYouTubeIframeAPIReady = () => {
      previousReady?.();
      resolve();
    };

    const script = document.createElement("script");
    script.src = "https://www.youtube.com/iframe_api";
    script.async = true;
    script.onerror = () => reject(new Error("Unable to load the YouTube player API."));
    document.head.appendChild(script);
  });

  return iframeApiPromise;
}

/**
 * Plays a track: Rust decodes and plays it (two decks, for gapless and crossfade), and the
 * YouTube IFrame player takes over a streamed track Rust could not get (see
 * `loadIframeFallback`).
 */
export class AudioEngine {
  /** What Rust has loaded on the active deck, or null. */
  private rustTrackId: string | null = null;
  /** What Rust has decoded on the standby deck, mirrored so `hasPreloaded` stays synchronous. */
  private rustStandbyTrackId: string | null = null;
  private rustDurationSec = 0;
  private rustStandbyDurationSec = 0;
  private player: YouTubePlayer | null = null;
  private playerHost: HTMLElement | null = null;
  private playerPromise: Promise<YouTubePlayer> | null = null;
  private currentVideoId: string | null = null;
  private volume = 1;
  private muted = false;
  private playbackRate = 1;
  private onEnded: (() => void) | null = null;
  private endedAt: { positionSec: number; durationSec: number } | null = null;
  private loadRequestId = 0;
  private stateWaiters = new Set<{
    states: Set<number>;
    videoId: string | null;
    resolve: () => void;
    reject: (error: Error) => void;
    timeoutId: number;
  }>();

  async loadTrack(videoId: string, source: RustAudioSource, durationSec?: number): Promise<void> {
    this.releaseIframePlayer();
    await this.loadRustAudio(videoId, source, durationSec ?? 0);
  }

  /**
   * Plays a track on the IFrame player instead.
   *
   * Rust resolves a signed googlevideo URL and can be refused; the IFrame player is Google's
   * own embed resolving its own URLs, so it is the one path that cannot 403. Costs the
   * `youtube.com` subframe for this track only — the next one tries Rust again.
   */
  async loadIframeFallback(videoId: string): Promise<void> {
    this.releaseRustAudio();
    await this.loadIframeTrack(videoId);
    logInternalWarn("AudioEngine fell back to the YouTube player", { videoId });
  }

  private async loadIframeTrack(videoId: string): Promise<void> {
    const requestId = ++this.loadRequestId;
    const player = await this.ensurePlayer();
    if (requestId !== this.loadRequestId) return;
    if (this.currentVideoId === videoId) return;

    this.currentVideoId = videoId;
    // A previous track may already have left the player in CUED. Wait for the
    // state event from this cue request instead of accepting that stale state.
    const cued = this.waitForPlayerState(
      [window.YT!.PlayerState.CUED],
      15_000,
      false,
      videoId,
    );
    player.cueVideoById(videoId);
    try {
      await cued;
    } catch (error) {
      if (requestId === this.loadRequestId && this.currentVideoId === videoId) {
        this.currentVideoId = null;
      }
      throw error;
    }
    if (requestId !== this.loadRequestId || this.currentVideoId !== videoId) return;
    logInternalInfo("AudioEngine.loadTrack cued", { videoId });
  }

  setOnEnded(listener: (() => void) | null): void {
    this.onEnded = listener;
  }

  /** Called by the process-wide Rust `ended` router, on the engine that owns playback. */
  handleRustEnded(): void {
    // Captured before `rustTrackId` goes, or both getters below fall back to zero and the
    // caller cannot tell a finished track from a stream that ran out.
    this.endedAt = { positionSec: this.getCurrentTime(), durationSec: this.getDuration() };
    this.rustTrackId = null;
    this.onEnded?.();
  }

  /** Position and duration as of the last `ended`. Consumed once. */
  takeEndedPlayback(): { positionSec: number; durationSec: number } | null {
    const snapshot = this.endedAt;
    this.endedAt = null;
    return snapshot;
  }

  /** The IFrame equivalent of `handleRustEnded`: snapshot, then notify. */
  private emitEnded(): void {
    this.endedAt = { positionSec: this.getCurrentTime(), durationSec: this.getDuration() };
    this.onEnded?.();
  }

  async play(): Promise<boolean> {
    const claimId = this.claimPlayback();
    if (this.rustTrackId) {
      await rustAudio.setVolume(this.volume, this.muted);
      await rustAudio.play();
      return claimId === playbackClaimId && playbackOwner === this;
    }
    const player = await this.ensurePlayer();
    if (claimId !== playbackClaimId || playbackOwner !== this) {
      player.pauseVideo();
      return false;
    }
    if (!this.currentVideoId) {
      throw new Error("No YouTube track is loaded.");
    }

    /*
     * A crossfade has already started this track on what is now the active deck. Reloading it
     * here would restart the song a second or two after the transition made it audible, so
     * the claim is all that is left to do.
     */
    if (
      player.getPlayerState() === window.YT!.PlayerState.PLAYING
      && player.getVideoData().video_id === this.currentVideoId
    ) {
      return claimId === playbackClaimId && playbackOwner === this;
    }

    if (this.muted) {
      player.mute();
    } else {
      player.unMute();
    }
    player.setVolume(this.getOutputVolumePercent());
    const videoId = this.currentVideoId;
    const playing = this.waitForPlayerState(
      [window.YT!.PlayerState.PLAYING],
      15_000,
      true,
      videoId,
    );
    const playerState = player.getPlayerState();
    if (
      playerState === window.YT!.PlayerState.CUED
      || playerState === window.YT!.PlayerState.UNSTARTED
    ) {
      logInternalInfo("AudioEngine.play starting cued YouTube video", {
        videoId,
        playerState,
        method: "loadVideoById",
      });
      player.loadVideoById(videoId);
    } else {
      logInternalInfo("AudioEngine.play starting YouTube video", {
        videoId,
        playerState,
        method: "playVideo",
      });
      player.playVideo();
    }
    try {
      await playing;
    } catch (error) {
      if (
        !isPlayerStateTimeout(error)
        || claimId !== playbackClaimId
        || playbackOwner !== this
      ) {
        throw error;
      }

      logInternalWarn("AudioEngine.play continuing after slow YouTube start", {
        videoId: this.currentVideoId,
        playerState: player.getPlayerState(),
        playerVideoId: player.getVideoData().video_id ?? null,
        error: error instanceof Error ? error.message : String(error),
      });
    }
    if (claimId !== playbackClaimId || playbackOwner !== this) {
      player.pauseVideo();
      return false;
    }
    logInternalInfo("AudioEngine.play requested", {
      videoId: this.currentVideoId,
      muted: this.muted,
      volume: this.volume,
    });
    return true;
  }

  pause(): void {
    if (this.rustTrackId) void rustAudio.pause().catch(() => {});
    this.player?.pauseVideo();
  }

  stop(): void {
    this.loadRequestId += 1;
    if (playbackOwner === this) {
      playbackOwner = null;
      playbackClaimId += 1;
    }
    this.releaseRustAudio();
    this.player?.stopVideo();
    this.currentVideoId = null;
    this.applyOutputVolume();
    this.rejectStateWaiters(new Error("Playback was stopped."));
  }

  silenceCompetingPlayback(): void {
    this.claimPlayback();
  }

  /**
   * Abandons whatever is mid-load on the active deck, without disturbing a standby that might
   * already hold (or be mid-decode for) the next track.
   *
   * The narrow alternative to `stop()` for a skip that lands before the previous load finished:
   * the listener is leaving the track that was loading, not the one preloading behind it.
   * `stop()`'s blanket teardown cleared both — Rust's `Command::Stop` clears every deck — which is
   * why a preload never survived a skip that arrived mid-load.
   */
  abandonActiveLoad(): void {
    this.loadRequestId += 1;
    this.rejectStateWaiters(new Error("Playback was abandoned."));

    if (this.rustTrackId) {
      this.rustTrackId = null;
      void rustAudio.dropActive().catch((error: unknown) => {
        rustAudio.warn("AudioEngine rust dropActive failed", error);
      });
    }
    this.player?.stopVideo();
    this.currentVideoId = null;
  }

  dispose(): void {
    this.stop();
    this.player?.destroy();
    this.playerHost?.remove();
    this.player = null;
    this.playerHost = null;
  }

  /**
   * Frees the IFrame player when Rust takes over again. It holds a `youtube.com` subframe
   * process, about 90 MB, which merely routing playback elsewhere leaves resident.
   */
  private releaseIframePlayer(): void {
    if (!this.player && !this.playerPromise) return;

    // Invalidates any cue or play still awaiting the player being torn down, so a late resolve
    // cannot write state for a player that no longer exists.
    this.loadRequestId += 1;
    this.player?.destroy();
    this.playerHost?.remove();
    this.player = null;
    this.playerHost = null;
    this.playerPromise = null;
    // So a later fallback actually cues into the fresh player instead of short-circuiting on
    // `currentVideoId === videoId`
    this.currentVideoId = null;
    logInternalInfo("AudioEngine.releaseIframePlayer", {});
  }

  seekTo(seconds: number): void {
    if (!Number.isFinite(seconds)) return;
    if (this.rustTrackId) {
      void rustAudio.seek(Math.max(0, seconds)).catch((error: unknown) => {
        rustAudio.warn("AudioEngine rust seek failed", error);
      });
      return;
    }
    this.player?.seekTo(Math.max(0, seconds), true);
  }

  /*
   * Deliberately silent.
   *
   * This is called on every pointer move of the volume slider. The eleven-field log that used
   * to live here read the YouTube player's volume twice, then went through `sanitizeForLog`,
   * `JSON.stringify`, an `invoke("frontend_log")` IPC hop that writes to a file, and a
   * `console.info` — sixty to a hundred and twenty times a second, for the duration of a drag.
   *
   * The diagnostics that justified them are still available where they cost nothing: `setMuted`
   * below logs, and mute is the state transition those investigations were actually about.
   */
  setVolume(level: number): void {
    this.volume = Math.min(1, Math.max(0, level));
    this.applyOutputVolume();
  }

  getVolume(): number {
    return this.volume;
  }

  setMuted(isMuted: boolean): void {
    // Logged on a change of state only: the whole settings object, muted included, is pushed
    // on every pointer move of the volume slider
    const changed = this.muted !== isMuted;
    this.muted = isMuted;
    if (isMuted) {
      this.player?.mute();
    } else {
      this.player?.unMute();
    }
    this.applyOutputVolume();
    if (!changed) return;
    logInternalInfo("AudioEngine.setMuted", {
      muted: this.muted,
      hasYouTubePlayer: Boolean(this.player),
      currentVideoId: this.currentVideoId,
    });
  }

  isMuted(): boolean {
    return this.muted;
  }

  getCurrentTime(): number {
    // Rust reports one position, for the track it loaded: the track id is the discriminator
    if (this.rustTrackId) {
      return rustAudio.getPositionTrackId() === this.rustTrackId ? rustAudio.getCurrentTime() : 0;
    }
    return this.player?.getCurrentTime() ?? 0;
  }

  getDuration(): number {
    if (this.rustTrackId) return this.rustDurationSec;
    return this.player?.getDuration() ?? 0;
  }

  /**
   * Decodes a track onto the Rust standby deck.
   *
   * Driven from `PlayerController.warmNextTrack`, which resolves the next track's `StreamData`
   * ahead of time.
   */
  async preloadRustTrack(
    trackId: string,
    source: RustAudioSource,
    durationSec: number,
  ): Promise<void> {
    if (!trackId || trackId === this.rustTrackId) return;
    if (this.rustStandbyTrackId === trackId) return;

    routeRustEnded();
    this.rustStandbyDurationSec = await rustAudio.load(trackId, source, durationSec, true);
    this.rustStandbyTrackId = trackId;
    logInternalInfo("AudioEngine rust preloaded", { trackId });
  }

  /** Whether a transition to `videoId` can skip loading entirely. */
  hasPreloaded(videoId: string): boolean {
    return this.rustStandbyTrackId === videoId;
  }

  /**
   * Hands playback to the preloaded deck, optionally over a crossfade.
   *
   * The whole transition happens in Rust: the standby deck is already decoded, so a zero fade
   * starts it and stops the outgoing one in the same tick (gapless), and a non-zero fade ramps
   * their volumes past each other on the audio thread.
   *
   * Returns false when there is nothing preloaded, leaving the caller to load normally.
   */
  async transitionToPreloaded(videoId: string, fadeMs: number): Promise<boolean> {
    if (!this.hasPreloaded(videoId)) return false;

    const swapped = await rustAudio.transition(videoId, Math.max(0, Math.round(fadeMs)));
    this.rustStandbyTrackId = null;
    if (!swapped) return false;
    this.rustTrackId = videoId;
    this.rustDurationSec = this.rustStandbyDurationSec;
    this.rustStandbyDurationSec = 0;
    this.currentVideoId = videoId;
    this.loadRequestId += 1;
    rustAudio.adoptTransitioned(videoId, this.rustDurationSec);
    logInternalInfo("AudioEngine.transitionToPreloaded", { videoId, fadeMs });
    return true;
  }

  /**
   * Decodes a track onto the active Rust deck.
   *
   * The `await` here is over the decoder reading the container header, not over the download:
   * a stream is published to Rust as an empty buffer sized from the URL's own `clen` and filled
   * behind this call, so what a click waits for is the first 128 KiB rather than the whole song.
   */
  private async loadRustAudio(
    videoId: string,
    source: RustAudioSource,
    durationSec: number,
  ): Promise<void> {
    const requestId = ++this.loadRequestId;
    routeRustEnded();

    // Dropping the standby first: it holds a decoded song, and a load that is not a transition
    // means whatever was queued behind the old track is no longer next.
    if (this.rustStandbyTrackId) {
      this.rustStandbyTrackId = null;
      this.rustStandbyDurationSec = 0;
      await rustAudio.dropStandby().catch(() => {});
    }

    const duration = await rustAudio.load(videoId, source, durationSec);
    if (requestId !== this.loadRequestId) return;

    this.rustTrackId = videoId;
    this.rustDurationSec = duration;
    this.currentVideoId = videoId;
    await rustAudio.setVolume(this.volume, this.muted);
    await rustAudio.setRate(this.playbackRate);
    logInternalInfo("AudioEngine rust audio loaded", {
      videoId,
      kind: source.kind,
      durationSec: duration,
    });
  }

  private releaseRustAudio(): void {
    if (!this.rustTrackId && !this.rustStandbyTrackId) return;
    // Not this engine's to stop when another took over playback since
    const ownsRustPlayback = playbackOwner === null || playbackOwner === this;
    this.rustTrackId = null;
    this.rustStandbyTrackId = null;
    this.rustDurationSec = 0;
    this.rustStandbyDurationSec = 0;
    if (!ownsRustPlayback) return;
    void rustAudio.stop().catch((error: unknown) => {
      rustAudio.warn("AudioEngine rust stop failed", error);
    });
  }

  /** 1 is normal speed. Applies to whichever player is currently playing. */
  setPlaybackRate(rate: number): void {
    this.playbackRate = Math.min(4, Math.max(0.25, rate));
    if (this.rustTrackId) {
      void rustAudio.setRate(this.playbackRate).catch((error: unknown) => {
        rustAudio.warn("AudioEngine rust rate failed", error);
      });
    }
    this.player?.setPlaybackRate?.(this.playbackRate);
  }

  getPlaybackRate(): number {
    return this.playbackRate;
  }

  private applyOutputVolume(): void {
    if (this.rustTrackId) {
      void rustAudio.setVolume(this.volume, this.muted).catch((error: unknown) => {
        rustAudio.warn("AudioEngine rust volume failed", error);
      });
    }
    this.player?.setVolume(this.getOutputVolumePercent());
  }

  private getOutputVolumePercent(): number {
    return this.muted ? 0 : Math.round(this.volume * 100);
  }

  private async ensurePlayer(): Promise<YouTubePlayer> {
    if (this.player) return this.player;
    if (this.playerPromise) return this.playerPromise;

    this.playerPromise = this.createPlayer().then((created) => {
      this.playerHost = created.host;
      return created.player;
    });
    try {
      this.player = await this.playerPromise;
      return this.player;
    } finally {
      this.playerPromise = null;
    }
  }

  private claimPlayback(): number {
    const claimId = ++playbackClaimId;
    playbackOwner = this;
    return claimId;
  }

  private async createPlayer(): Promise<{ player: YouTubePlayer; host: HTMLElement }> {
    await loadYouTubeIframeApi();
    if (!window.YT?.Player) {
      throw new Error("YouTube player API loaded without a Player constructor.");
    }

    /*
     * The IFrame player has to exist, at a real size, on screen.
     *
     * YouTube refuses to start playback in a player that is display:none, visibility:hidden or
     * effectively zero-sized, so it cannot simply be hidden — which is why this is a 200px box
     * held at 1% opacity rather than removed. That opacity is not enough on its own: a bright
     * video thumbnail is still legible over a flat background, and it showed as a faded square
     * in the bottom-right corner from the moment the first song played.
     *
     * A negative z-index puts it behind the app's own opaque background instead. The element
     * keeps its position, its size and its opacity, so none of the heuristics YouTube uses to
     * detect a hidden player change — it is simply painted underneath something.
     */
    const host = document.createElement("div");
    host.style.position = "fixed";
    /*
     * Inset rather than flush to the corner: html/body/#root are transparent so the window's
     * rounded corners cut out, which leaves a notch where a corner-pinned box would show
     * through from behind the app rather than being covered by it.
     */
    host.style.right = "24px";
    host.style.bottom = "24px";
    host.style.width = "200px";
    host.style.height = "200px";
    host.style.opacity = "0.01";
    host.style.pointerEvents = "none";
    host.style.zIndex = "-1";
    const target = document.createElement("div");
    host.appendChild(target);
    document.body.appendChild(host);

    return new Promise((resolve, reject) => {
      let player: YouTubePlayer;
      const timeoutId = window.setTimeout(() => {
        player?.destroy();
        host.remove();
        reject(new Error("Timed out while creating the YouTube player."));
      }, 15_000);

      player = new window.YT!.Player(target, {
        width: 200,
        height: 200,
        playerVars: {
          autoplay: 0,
          controls: 0,
          disablekb: 1,
          enablejsapi: 1,
          origin: window.location.origin,
          playsinline: 1,
          widget_referrer: "https://music.youtube.com/",
        },
        events: {
          onReady: () => {
            window.clearTimeout(timeoutId);
            allowYouTubeIframePlayback(host);
            player.setVolume(this.getOutputVolumePercent());
            if (this.muted) {
              player.mute();
            } else {
              player.unMute();
            }
            logInternalInfo("AudioEngine YouTube player ready");
            resolve({ player, host });
          },
          onStateChange: (event) => {
            // Events from a player that is not (yet, or any longer) this engine's are not its
            // playback
            const isActiveDeck = player === this.player;
            logInternalInfo("AudioEngine YouTube player state", {
              state: event.data,
              videoId: this.currentVideoId,
              playerVideoId: player.getVideoData().video_id ?? null,
            });
            if (!isActiveDeck) return;

            this.resolveStateWaiters(event.data, player.getVideoData().video_id ?? null);
            if (event.data === window.YT!.PlayerState.ENDED) {
              this.emitEnded();
            }
          },
          onError: (event) => {
            const error = new Error(`YouTube player error ${event.data}`);
            if (player !== this.player) return;
            this.rejectStateWaiters(error);
            logInternalError("AudioEngine YouTube player error", error, {
              videoId: this.currentVideoId,
            });
          },
        },
      });
    });
  }

  private waitForPlayerState(
    states: number[],
    timeoutMs: number,
    acceptCurrentState = true,
    videoId: string | null = null,
  ): Promise<void> {
    if (acceptCurrentState) {
      const currentState = this.player?.getPlayerState();
      const currentVideoId = this.player?.getVideoData().video_id ?? null;
      if (
        currentState !== undefined
        && states.includes(currentState)
        && (!videoId || currentVideoId === videoId)
      ) {
        return Promise.resolve();
      }
    }

    return new Promise((resolve, reject) => {
      const waiter = {
        states: new Set(states),
        videoId,
        resolve,
        reject,
        timeoutId: 0,
      };

      waiter.timeoutId = window.setTimeout(() => {
        this.stateWaiters.delete(waiter);
        reject(new Error(`Timed out waiting for YouTube player state: ${states.join(", ")}.`));
      }, timeoutMs);

      this.stateWaiters.add(waiter);
    });
  }

  private resolveStateWaiters(state: number, videoId: string | null): void {
    for (const waiter of this.stateWaiters) {
      if (
        !waiter.states.has(state)
        || (waiter.videoId !== null && waiter.videoId !== videoId)
      ) {
        continue;
      }
      window.clearTimeout(waiter.timeoutId);
      this.stateWaiters.delete(waiter);
      waiter.resolve();
    }
  }

  private rejectStateWaiters(error: Error): void {
    for (const waiter of this.stateWaiters) {
      window.clearTimeout(waiter.timeoutId);
      waiter.reject(error);
    }
    this.stateWaiters.clear();
  }
}
