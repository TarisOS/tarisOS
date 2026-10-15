// Modified for TarisOS (Taris Music) by George Dobreff ("Witcher") and contributors, 2026.
import { useCallback, useRef, useSyncExternalStore } from "react";
import { YouTubeMusicDataSource } from "../datasource/youtube/YouTubeMusicDataSource";
import { LibraryController } from "./LibraryController";
import { PlayerController, type PlayerSession, type PlayerState } from "./PlayerController";
import { SearchController } from "./SearchController";
import { loadAppSession } from "./appSession";
import { readSessionRestoreEnabled } from "../ui/settings/sessionRestore";
import {
  hydrateOfflineStore,
  setOfflineStreamResolver,
  startOfflineProgressFeed,
} from "./offlineStore";

const dataSource = new YouTubeMusicDataSource();

export const libraryController = new LibraryController(dataSource);
export const searchController = new SearchController(dataSource);
/*
 * The offline queue needs a stream URL but must not depend on any particular data source, so
 * the source is injected here where both are already in scope.
 */
setOfflineStreamResolver((track, quality) => {
  /*
   * `resolveDownloadUrl`, never `resolveStreamUrl`. The two differ only in client order, but
   * the download one never reads the authenticated-streaming preference — binding it here is
   * what keeps that guarantee at the wiring site rather than inside a shared function.
   */
  const resolver = (dataSource as {
    resolveDownloadUrl?: (
      t: typeof track,
      q: typeof quality,
    ) => Promise<{ url: string; mimeType: string; cookie?: string }>;
  }).resolveDownloadUrl;
  if (!resolver) throw new Error("Downloads are unavailable for this source.");
  return resolver.call(dataSource, track, quality);
});
void hydrateOfflineStore();
startOfflineProgressFeed();

/** The app's one player. */
export const player = new PlayerController(dataSource);
/* `exportSession()` builds a fresh object each call; the session is cached until the player
   changes, so `useSyncExternalStore` sees a stable snapshot. Subscribed first, so the cache is
   cleared before any component reads it. */
let sessionSnapshot: PlayerSession | undefined;
player.subscribe(() => {
  sessionSnapshot = undefined;
});
/*
 * Read once, at module scope, before anything can toggle it. Restoring is all-or-nothing for a
 * given launch — half a session is worse than none.
 */
const restoredSession = readSessionRestoreEnabled() ? loadAppSession() : null;
if (restoredSession) {
  player.restoreSession(restoredSession.player);
}

type PlayerControllerMethod =
  | "loadTrack"
  | "playTrackById"
  | "play"
  | "pause"
  | "togglePlayPause"
  | "addToQueue"
  | "playNext"
  | "skipToNext"
  | "seekTo"
  | "setVolume"
  | "skipToPrevious"
  | "getCurrentTime"
  | "getDuration"
  | "getVolume"
  | "isMuted"
  | "toggleMute"
  | "getPlaybackOrderMode"
  | "cyclePlaybackOrderMode"
  | "toggleShuffle"
  | "setShuffleEnabled"
  | "setPlaybackOrderMode"
  | "setPlaybackRate"
  | "getPlaybackRate"
  | "setSleepTimer"
  | "getSleepTimerRemainingMs"
  | "getLyrics"
  | "getPlayerSession"
  | "removeFromQueueAt"
  | "playQueueTrackAt"
  | "moveQueueTrack"
  | "shuffleUpcomingQueue"
  | "shuffleEntirePlaylist"
  | "clearUpcomingQueue"
  | "addTracksToQueue"
  | "setStopAfterQueueIndex"
  | "generateQueueAfter";

export type PlayerControllerActions = Pick<PlayerController, PlayerControllerMethod>;

class PlayerActions implements PlayerControllerActions {
  loadTrack = (track: Parameters<PlayerController["loadTrack"]>[0]) => player.loadTrack(track);
  playTrackById = (
    videoId: string,
    playbackQueue?: Parameters<PlayerController["playTrackById"]>[1],
    autoplayWhenQueueEnds?: Parameters<PlayerController["playTrackById"]>[2],
    shufflePlaylist?: Parameters<PlayerController["playTrackById"]>[3],
  ) => player.playTrackById(
    videoId,
    playbackQueue,
    autoplayWhenQueueEnds,
    shufflePlaylist,
  );
  play = () => player.play();
  pause = () => player.pause();
  togglePlayPause = () => player.togglePlayPause();
  addToQueue = (track: Parameters<PlayerController["addToQueue"]>[0]) =>
    player.addToQueue(track);
  playNext = (track: Parameters<PlayerController["playNext"]>[0]) =>
    player.playNext(track);
  skipToNext = () => player.skipToNext();
  seekTo = (time: number) => player.seekTo(time);
  /*
   * No logging here either — see AudioEngine.setVolume. This ran two full log writes per
   * pointer move of the slider, each one reading the player state twice to build its payload.
   */
  setVolume = async (level: number) => {
    const volume = Math.min(1, Math.max(0, level));
    await player.setVolume(volume, volume === 0);
    player.applyPlaybackSettings({
      volume: player.getVolume(),
      muted: player.isMuted(),
    }, false);
  };
  skipToPrevious = () => player.skipToPrevious();
  getCurrentTime = () => player.getCurrentTime();
  getDuration = () => player.getDuration();
  getVolume = () => player.getVolume();
  isMuted = () => player.isMuted();
  toggleMute = async () => {
    await player.toggleMute();
    player.applyPlaybackSettings({
      volume: player.getVolume(),
      muted: player.isMuted(),
    }, false);
  };
  getPlaybackOrderMode = () => player.getPlaybackOrderMode();
  cyclePlaybackOrderMode = () => player.cyclePlaybackOrderMode();
  toggleShuffle = () => player.toggleShuffle();
  setShuffleEnabled = (enabled: boolean) =>
    player.setShuffleEnabled(enabled);
  setPlaybackOrderMode = (mode: Parameters<PlayerController["setPlaybackOrderMode"]>[0]) =>
    player.setPlaybackOrderMode(mode);
  setPlaybackRate = (rate: number) => player.setPlaybackRate(rate);
  getPlaybackRate = () => player.getPlaybackRate();
  setSleepTimer = (minutes: number | null) =>
    player.setSleepTimer(minutes);
  getSleepTimerRemainingMs = () =>
    player.getSleepTimerRemainingMs();
  getLyrics = (track: Parameters<PlayerController["getLyrics"]>[0]) =>
    player.getLyrics(track);
  getPlayerSession = () => player.exportSession();
  removeFromQueueAt = (index: number) => player.removeFromQueueAt(index);
  playQueueTrackAt = (index: number) => player.playQueueTrackAt(index);
  moveQueueTrack = (
    sourceIndex: number,
    targetIndex: number,
    insertAfter: boolean,
  ) => player.moveQueueTrack(sourceIndex, targetIndex, insertAfter);
  shuffleUpcomingQueue = () => player.shuffleUpcomingQueue();
  shuffleEntirePlaylist = () => player.shuffleEntirePlaylist();
  clearUpcomingQueue = () => player.clearUpcomingQueue();
  addTracksToQueue = (tracks: Parameters<PlayerController["addTracksToQueue"]>[0]) =>
    player.addTracksToQueue(tracks);
  setStopAfterQueueIndex = (index: number | null) =>
    player.setStopAfterQueueIndex(index);
  generateQueueAfter = (index: number) =>
    player.generateQueueAfter(index);
}

export const playerController: PlayerControllerActions = new PlayerActions();

/*
 * Hoisted, not inline.
 *
 * `useSyncExternalStore` treats a new `subscribe` identity as a new subscription: it tears
 * the old one down and re-establishes it in a layout effect. Written inline these were a
 * fresh closure on every render, so every consumer re-subscribed on every render for the
 * life of the app.
 */
const subscribeToPlayer = (listener: () => void) => player.subscribe(listener);
const subscribeToLibrary = (listener: () => void) => libraryController.subscribe(listener);
const getPlayerState = () => player.getState();
const getPlayerSession = () => (sessionSnapshot ??= player.exportSession());
const getLibraryState = () => libraryController.getState();

/** Re-exported so selector call sites need one import, not two. */
export { shallowEqual } from "../internal/shallowEqual";

/**
 * Subscribes to a slice of a store instead of the whole thing.
 *
 * The player state is one object, so subscribing to the whole thing re-renders on any change
 * to any field — dragging the volume slider used to re-render the entire application,
 * because the root subscribed to the same object as the volume control did.
 *
 * The cache is what makes an object-returning selector legal here: `useSyncExternalStore`
 * compares snapshots with `Object.is` and calls `getSnapshot` more than once per render, so
 * a selector building a fresh object every call would loop forever and warn. Holding the
 * previous value when the comparison says nothing changed is what keeps it stable.
 */
function useStoreSelector<S, T>(
  subscribe: (listener: () => void) => () => void,
  getState: () => S,
  select: (state: S) => T,
  isEqual: (a: T, b: T) => boolean = Object.is,
): T {
  /* Both are read through refs because callers pass inline arrows: as dependencies they
     would change identity every render and defeat the memoisation they exist to provide. */
  const selectRef = useRef(select);
  selectRef.current = select;
  const isEqualRef = useRef(isEqual);
  isEqualRef.current = isEqual;
  const cacheRef = useRef<{ state: S; value: T } | null>(null);

  const getSnapshot = useCallback(() => {
    const state = getState();
    const cached = cacheRef.current;
    if (cached && Object.is(cached.state, state)) return cached.value;

    const next = selectRef.current(state);
    if (cached && isEqualRef.current(cached.value, next)) {
      // Same selection, new state object: keep the old reference so React sees no change.
      cacheRef.current = { state, value: cached.value };
      return cached.value;
    }
    cacheRef.current = { state, value: next };
    return next;
  }, [getState]);

  return useSyncExternalStore(subscribe, getSnapshot, getSnapshot);
}

/**
 * Prefer this over subscribing to the whole player state in anything that reads one or two
 * fields.
 *
 * Pass `shallowEqual` when the selector returns an object; the default `Object.is` is right
 * for the common case of selecting a single field or a derived boolean.
 */
export function usePlayerSelector<T>(
  select: (state: PlayerState) => T,
  isEqual?: (a: T, b: T) => boolean,
): T {
  return useStoreSelector(subscribeToPlayer, getPlayerState, select, isEqual);
}

export function usePlayerSession() {
  return useSyncExternalStore(subscribeToPlayer, getPlayerSession, getPlayerSession);
}

/**
 * A slice of the session, cached the same way `usePlayerSelector` caches player state.
 *
 * `exportSession()` rebuilds the queue window with `.slice()` on every export — a fresh array
 * even when the tracks in it have not changed — and every player emit triggers one, including
 * ones with nothing to do with the queue (a volume drag fires dozens per gesture). Plain
 * `usePlayerSession` has no caching, so a component reading `.queue` off it recomputes and
 * re-renders on all of those. Route queue-only reads through here instead.
 */
export function usePlayerSessionSelector<T>(
  select: (session: PlayerSession | null) => T,
  isEqual?: (a: T, b: T) => boolean,
): T {
  return useStoreSelector(subscribeToPlayer, getPlayerSession, select, isEqual);
}

export function useLibraryState() {
  return useSyncExternalStore(subscribeToLibrary, getLibraryState, getLibraryState);
}
