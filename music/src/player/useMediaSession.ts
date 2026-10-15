// Modified for TarisOS (Taris Music) by George Dobreff ("Witcher") and contributors, 2026.
import { useCallback, useEffect } from "react";
import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import type { PlayerState } from "./PlayerController";
import type { PlayerControllerActions } from "./playerStore";
import { logInternalWarn } from "../internal/logging";

type NativeMediaAction =
  | "play"
  | "pause"
  | "playPause"
  | "next"
  | "previous"
  | { action: "seekTo"; positionSec: number };

/*
 * The app registers its own MPRIS2 D-Bus interface (`linux_media.rs`, via souvlaki) rather than
 * relying on WebKitGTK's own bridge, because the bridge doesn't surface next/previous through
 * the desktop widget or media keys.
 */
const NATIVE_MEDIA_COMMAND = "update_linux_media_session";
const NATIVE_MEDIA_CONTROL_EVENT = "linux-media-control";

function getClampedPosition(duration: number, position: number): number {
  const safePosition = Number.isFinite(position) ? Math.max(0, position) : 0;
  if (!Number.isFinite(duration) || duration <= 0) return safePosition;
  return Math.min(duration, safePosition);
}

/**
 * Only the two fields this actually reads.
 *
 * Taking the whole `PlayerState` made every caller a subscriber to all of it — including
 * volume, which commits on every pointer move — to satisfy a signature that never looked at
 * more than the track and the status.
 */
type MediaSessionState = Pick<PlayerState, "currentTrack" | "status">;

export function useMediaSession(
  state: MediaSessionState,
  controller: PlayerControllerActions,
): void {
  const sendNativeMediaUpdate = useCallback((context: string, forceMetadata = false) => {
    const track = state.currentTrack;
    const duration = controller.getDuration() || track?.durationSec || 0;
    void invoke(NATIVE_MEDIA_COMMAND, {
      update: {
        title: track?.title ?? null,
        artist: track?.artist ?? null,
        artworkUrl: track?.artworkUrl ?? null,
        status: state.status,
        durationSec: duration || null,
        positionSec: getClampedPosition(duration, controller.getCurrentTime()),
        forceMetadata,
      },
    }).catch((error) => {
      logInternalWarn(`useMediaSession native ${context} update failed`, {
        error: String(error),
      });
    });
  }, [controller, state.currentTrack, state.status]);

  useEffect(() => {
    const unlistenPromise = listen<NativeMediaAction>(
      NATIVE_MEDIA_CONTROL_EVENT,
      ({ payload }) => {
        if (typeof payload === "object") {
          if (payload.action === "seekTo") void controller.seekTo(payload.positionSec);
          return;
        }

        if (payload === "play") void controller.play();
        if (payload === "pause") void controller.pause();
        if (payload === "playPause") void controller.togglePlayPause();
        if (payload === "next") void controller.skipToNext();
        if (payload === "previous") void controller.skipToPrevious();
      },
    );

    return () => {
      void unlistenPromise.then((unlisten) => unlisten());
    };
  }, [controller]);

  useEffect(() => {
    sendNativeMediaUpdate("state", true);
    const retryDelaysMs = [250, 1000, 2500];
    const retryIds = retryDelaysMs.map((delayMs) => (
      window.setTimeout(() => sendNativeMediaUpdate("state retry", true), delayMs)
    ));
    return () => retryIds.forEach((retryId) => window.clearTimeout(retryId));
  }, [sendNativeMediaUpdate]);

  /*
   * Position goes out once per second while playing, and once per transition otherwise.
   *
   * The OS needs a fresh position for its scrubber, but a paused track's position is fresh
   * already — this was an IPC call every second for as long as a track was loaded, whether or
   * not it was moving. `state.status` is a dependency so pausing, resuming and seeking each
   * still push one update immediately.
   */
  useEffect(() => {
    if (!state.currentTrack) return;

    sendNativeMediaUpdate("position");
    if (state.status !== "playing") return;

    const intervalId = window.setInterval(
      () => sendNativeMediaUpdate("position"),
      1000,
    );
    return () => window.clearInterval(intervalId);
  }, [sendNativeMediaUpdate, state.currentTrack, state.status]);

  /*
   * WebKitGTK's own bridge stays empty: with it, the desktop would show a second now-playing
   * entry and media keys would fire twice.
   */
  useEffect(() => {
    if (!("mediaSession" in navigator)) return;
    try {
      navigator.mediaSession.metadata = null;
      navigator.mediaSession.playbackState = "none";
      for (const action of [
        "play", "pause", "stop", "nexttrack", "previoustrack",
        "seekto", "seekbackward", "seekforward",
      ] as MediaSessionAction[]) {
        navigator.mediaSession.setActionHandler(action, null);
      }
    } catch {
      // WebView media-session support varies by installed runtime version.
    }
  }, []);
}
