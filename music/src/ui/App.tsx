// Modified for TarisOS (Taris Music) by George Dobreff ("Witcher") and contributors, 2026.
import { useCallback, useEffect, useRef, useState } from "react";
import { AnimatePresence, MotionConfig } from "motion/react";
import type { Album, Artist, Playlist, SearchResults, Track } from "../datasource/types";
import { looksLikeYouTubeLink } from "../datasource/youtube/links";
import { useDisableContextMenu } from "./hooks/useDisableContextMenu";
import { HomePage } from "./pages/HomePage";

/*
 * TarisOS: every page imported up front. Loading each on its first visit showed an empty frame
 * while its code loaded: the page blinked out and back the first time each one was opened.
 */
import { AlbumView } from "./pages/AlbumView";
import { ArtistView } from "./pages/ArtistView";
import { PlaylistView } from "./pages/PlaylistView";
import { RelatedPage } from "./pages/RelatedPage";
import { SearchResultsPage } from "./pages/SearchResultsPage";
import { LibraryPage } from "./pages/LibraryPage";
import { BrowsePage } from "./pages/BrowsePage";
import { HistoryPage } from "./pages/HistoryPage";
import { SettingsPage } from "./pages/SettingsPage";
import { LyricsView } from "./pages/LyricsView";
import { SearchOverlay } from "./components/SearchOverlay";
import { TrackContextMenuProvider } from "./components/TrackContextMenu";
import { ErrorBoundary } from "./components/ErrorBoundary";
import { PlaylistContextMenuProvider } from "./components/PlaylistContextMenu";
import { ArtistNavigationProvider } from "./components/ArtistLinks";
import { cn } from "@/lib/utils";
import { TitleBar } from "./components/TitleBar";
import { PlayerBar } from "./components/player/PlayerBar";
import { QueuePanel } from "./components/player/QueuePanel";
import { useQueuePanelCollapsed } from "./settings/queuePanel";

/** Wide enough for a 44px cover plus breathing room, matching the sidebar rail's feel. */
const COLLAPSED_QUEUE_WIDTH = 62;
import { Layout } from "./components/Layout";
import type { Page, PageState } from "./types/page";
import {
  libraryController,
  player,
  playerController,
  searchController,
  useLibraryState,
  usePlayerSession,
  usePlayerSelector,
  shallowEqual,
} from "../player/playerStore";
import {
  clearAppSession,
  loadAppSession,
  saveAppSession,
  savePlaybackPosition,
} from "../player/appSession";
import { useMediaSession } from "../player/useMediaSession";
import { LastFmService } from "../player/LastFm";
import { playerUIStore, usePlayerUIState } from "./stores/playerUIStore";
import { AppLoadingScreen } from "./components/AppLoadingScreen";
import { AuthOverlay } from "./components/AuthOverlay";
import { clearAppSettings } from "../internal/appSettings";
import { clearCache } from "../internal/cache";
import { useReduceMotion } from "./settings/renderEffects";

import { listen } from "@tauri-apps/api/event";
import { getCurrentWindow } from "@tauri-apps/api/window";
import { logInternalWarn } from "../internal/logging";
import { eventMatchesShortcut, useKeyboardShortcuts } from "./settings/keyboardShortcuts";
import { useLastFmScrobblingEnabled } from "./settings/lastfm";
import { readSessionRestoreEnabled } from "./settings/sessionRestore";
import { hydratePlaybackSettings } from "../player/playbackSettings";
const restoredSession = readSessionRestoreEnabled() ? loadAppSession() : null;
const LOADING_SCREEN_FADE_MS = 80;
const LOADING_SCREEN_MAX_MS = 4000;
const LOADING_SCREEN_MIN_MS = 1000;
const MOUSE_BACK_BUTTON = 3;
const MOUSE_FORWARD_BUTTON = 4;
/** How often the playback position is written while playing, for a restore after a crash. */
const SESSION_HEARTBEAT_MS = 5000;
const SLEEP_RECOVERY_TIMER_INTERVAL_MS = 15000;
const SLEEP_RECOVERY_TIMER_DRIFT_MS = 60000;
/**
 * How many pages back the app remembers.
 *
 * Each entry is a whole view — a playlist's entire track list, a page of search results — so an
 * uncapped stack grows by a hundred-odd KB per page navigated, for as long as the app
 * stays open. Nothing reads deeper than the user can click, and fifty is well past that.
 */
const MAX_NAVIGATION_HISTORY = 50;

function pushNavigationState(
  entries: readonly PageState[],
  state: PageState,
): PageState[] {
  return [...entries, state].slice(-MAX_NAVIGATION_HISTORY);
}

function getNavigationState(page: Page): PageState {
  return {
    title: page.title,
    view: page.view,
    browseTab: page.browseTab,
    album: page.album,
    artist: page.artist,
    playlist: page.playlist,
    relatedTrack: page.relatedTrack,
    searchQuery: page.searchQuery,
    searchResults: page.searchResults,
    mixedSearchResults: page.mixedSearchResults,
    searchLoading: page.searchLoading,
  };
}

function getNavigationKey(state: PageState): string {
  switch (state.view) {
    case "album":
      return `album:${state.album?.id ?? ""}`;
    case "artist":
      return `artist:${state.artist?.id ?? state.artist?.name ?? ""}`;
    case "playlist":
      return `playlist:${state.playlist?.id ?? ""}`;
    case "related":
      return `related:${state.relatedTrack?.id ?? ""}`;
    case "search":
      return `search:${state.searchQuery ?? ""}`;
    case "home":
      return "home";
    case "history":
      return "history";
    case "browse":
      return `browse:${state.browseTab ?? ""}`;
    case "library":
      return "library";
  }
}

function applyNavigationState(page: Page, state: PageState): Page {
  return {
    ...page,
    title: state.title,
    view: state.view,
    browseTab: state.browseTab,
    album: state.album,
    artist: state.artist,
    playlist: state.playlist,
    relatedTrack: state.relatedTrack,
    searchQuery: state.searchQuery,
    searchResults: state.searchResults,
    mixedSearchResults: state.mixedSearchResults,
    searchLoading: state.searchLoading,
  };
}

function stripNavigationHistory(page: Page): Page {
  const { navigationHistory, ...sessionPage } = page;
  void navigationHistory;
  return sessionPage;
}

export default function App() {
  useDisableContextMenu();
  const libraryState = useLibraryState();
  /*
   * Only the three fields the root actually reads. Selecting the whole state here made the
   * application's largest component a subscriber to every field of it, including volume —
   * which commits on every pointer move of the slider. Narrowing it is also self-enforcing:
   * reading a field that is not selected is a type error rather than stale data.
   */
  const playerState = usePlayerSelector(
    (state) => ({
      currentTrack: state.currentTrack,
      status: state.status,
      error: state.error,
    }),
    shallowEqual,
  );
  const playerSession = usePlayerSession();
  const playerUIState = usePlayerUIState();
  const keyboardShortcuts = useKeyboardShortcuts();
  const lastFmScrobblingEnabled = useLastFmScrobblingEnabled();
  // The stylesheet kills CSS animation via !important; this is the JS half. Motion writes
  // inline styles, so no stylesheet can reach it — and its own `useReducedMotion` reads the
  // OS media query alone, which is why this is the app's hook and not that one.
  const reduceMotion = useReduceMotion();

  // Full-screen lyrics is real OS fullscreen, not just a wider layout — the whole point is
  // the window chrome getting out of the way too.
  useEffect(() => {
    void getCurrentWindow()
      .setFullscreen(playerUIState.isLyricsFullscreen)
      .catch((error) => {
        logInternalWarn("App.syncLyricsFullscreen failed", {
          error: error instanceof Error ? error.message : String(error),
        });
      });
  }, [playerUIState.isLyricsFullscreen]);

  // The page on screen (the saved session's, or home), and Settings over it while it's open
  const [page, setPage] = useState<Page>(
    () => (restoredSession ? stripNavigationHistory(restoredSession.page) : { view: "home" }),
  );
  const [settingsOpen, setSettingsOpen] = useState(false);
  const [isSearchOpen, setIsSearchOpen] = useState(false);
  /*
   * The sidebar is a fixed icon rail. 72px sits below the Sidebar's own text-hide threshold,
   * so every row renders as artwork only and explains itself through a tooltip on hover.
   * Still state rather than a constant because TitleBar aligns its home button to this width.
   */
  const [sidebarWidth, setSidebarWidth] = useState(62);
  const [queuePanelWidth, setQueuePanelWidth] = useState(340);
  const isQueuePanelCollapsed = useQueuePanelCollapsed();
  const [loadingScreenState, setLoadingScreenState] = useState<"visible" | "leaving" | "hidden">("visible");
  useEffect(() => {
    let cancelled = false;
    void hydratePlaybackSettings().then((settings) => {
      if (cancelled) return;
      player.applyPlaybackSettings(settings, false);
    });

    return () => {
      cancelled = true;
    };
  }, []);

  const loadingScreenDismissedRef = useRef(false);
  const loadingScreenStartedAtRef = useRef(performance.now());
  const lastErrorAlertRef = useRef<string | null>(null);
  const pageRef = useRef(page);
  const sessionPersistenceDisabledRef = useRef(false);
  const sleepRecoveryLastTickRef = useRef(Date.now());
  const sleepRecoveryReloadingRef = useRef(false);
  pageRef.current = page;
  const persistAppSession = useCallback(() => {
    if (sessionPersistenceDisabledRef.current) return;
    saveAppSession({
      version: 2,
      page: { ...stripNavigationHistory(pageRef.current), searchLoading: false },
      player: player.exportSession(),
    });
  }, []);
  const persistPlaybackPosition = useCallback(() => {
    if (sessionPersistenceDisabledRef.current) return;
    savePlaybackPosition(player.getState().currentTrack?.id, player.getCurrentTime());
  }, []);

  const isQueuePanelOpen = page.isQueueOpen ?? false;
  const canNavigateBack = (page.navigationHistory?.back.length ?? 0) > 0;
  const canNavigateForward = (page.navigationHistory?.forward.length ?? 0) > 0;

  const dismissLoadingScreen = useCallback(() => {
    if (loadingScreenDismissedRef.current) return;

    loadingScreenDismissedRef.current = true;
    setLoadingScreenState("leaving");
    window.setTimeout(() => {
      setLoadingScreenState("hidden");
    }, LOADING_SCREEN_FADE_MS);
  }, []);

  // A page opened from anywhere, Settings included, closes Settings
  const navigate = useCallback((nextState: PageState) => {
    setSettingsOpen(false);
    setPage((current) => {
      const currentState = getNavigationState(current);
      const next = applyNavigationState(current, nextState);
      if (getNavigationKey(currentState) === getNavigationKey(nextState)) {
        return next;
      }

      return {
        ...next,
        navigationHistory: {
          back: pushNavigationState(current.navigationHistory?.back ?? [], currentState),
          forward: [],
        },
      };
    });
  }, []);

  const updateSearchPage = useCallback((query: string, nextState: PageState) => {
    setPage((current) => {
      const updateHistoryState = (state: PageState) =>
        state.view === "search" && state.searchQuery === query
          ? nextState
          : state;
      const navigationHistory = current.navigationHistory
        ? {
            back: current.navigationHistory.back.map(updateHistoryState),
            forward: current.navigationHistory.forward.map(updateHistoryState),
          }
        : undefined;

      if (current.searchQuery !== query) {
        return { ...current, navigationHistory };
      }

      return {
        ...applyNavigationState(current, nextState),
        navigationHistory,
      };
    });
  }, []);

  const handleNavigateBack = useCallback(() => {
    playerUIStore.setLyricsOpen(false);
    setPage((current) => {
      const back = current.navigationHistory?.back ?? [];
      if (back.length === 0) return current;

      const currentState = getNavigationState(current);
      return {
        ...applyNavigationState(current, back[back.length - 1]),
        navigationHistory: {
          back: back.slice(0, -1),
          forward: [currentState, ...(current.navigationHistory?.forward ?? [])],
        },
      };
    });
  }, []);

  const handleNavigateForward = useCallback(() => {
    playerUIStore.setLyricsOpen(false);
    setPage((current) => {
      const forward = current.navigationHistory?.forward ?? [];
      if (forward.length === 0) return current;

      const currentState = getNavigationState(current);
      return {
        ...applyNavigationState(current, forward[0]),
        navigationHistory: {
          back: pushNavigationState(current.navigationHistory?.back ?? [], currentState),
          forward: forward.slice(1),
        },
      };
    });
  }, []);

  const setIsQueuePanelOpen = useCallback((open: boolean) => {
    setPage((current) => ({ ...current, isQueueOpen: open }));
  }, []);

  useMediaSession(playerState, playerController);

  useEffect(() => {
    const syncLastFm = () => {
      LastFmService.updatePlayback({
        track: playerState.currentTrack,
        status: playerState.status,
        currentTime: playerController.getCurrentTime(),
        duration: playerController.getDuration(),
        enabled: lastFmScrobblingEnabled,
      });
    };

    /*
     * The single call is the one that matters on every other status: it is what tells the
     * scrobbler a track was paused, changed or stopped. The interval exists only to watch a
     * playing track cross its scrobble threshold, so it has nothing to do while the position
     * is not moving — and it was running once a second for the whole session regardless, with
     * scrobbling switched off, with nothing loaded, engine reads and all.
     */
    syncLastFm();
    if (!lastFmScrobblingEnabled || playerState.status !== "playing") return;

    const intervalId = window.setInterval(syncLastFm, 1000);
    return () => window.clearInterval(intervalId);
  }, [
    lastFmScrobblingEnabled,
    playerState.currentTrack,
    playerState.status,
  ]);

  const activeViewKey = settingsOpen
    ? "settings"
    : [
      page.view,
      page.browseTab,
      page.album?.id,
      page.artist?.id,
      page.playlist?.id,
      page.searchQuery,
    ].filter(Boolean).join(":");

  const handleNavigateHome = () => {
    playerUIStore.setLyricsOpen(false);
    navigate({ view: "home" });
  };

  useEffect(() => {
    void libraryController.initialize();
  }, []);

  useEffect(() => {
    if (libraryState.status !== "error" || !libraryState.error) return;
    const message = `YouTube Music sign-in or library sync failed:\n\n${libraryState.error}`;
    if (lastErrorAlertRef.current === message) return;
    lastErrorAlertRef.current = message;
    window.alert(message);
  }, [libraryState.error, libraryState.status]);

  useEffect(() => {
    if (playerState.status !== "error" || !playerState.error) return;
    const message = `Playback failed:\n\n${playerState.error}`;
    if (lastErrorAlertRef.current === message) return;
    lastErrorAlertRef.current = message;
    window.alert(message);
  }, [playerState.error, playerState.status]);

  useEffect(() => {
    const elapsed = performance.now() - loadingScreenStartedAtRef.current;
    const remainingMaximum = Math.max(0, LOADING_SCREEN_MAX_MS - LOADING_SCREEN_FADE_MS - elapsed);
    const maxTimer = window.setTimeout(dismissLoadingScreen, remainingMaximum);

    return () => {
      window.clearTimeout(maxTimer);
    };
  }, [dismissLoadingScreen]);

  useEffect(() => {
    const hasRenderableLibrary = Boolean(libraryState.library);
    if (
      !hasRenderableLibrary
      && (libraryState.status === "restoring" || libraryState.status === "loading")
    ) {
      return;
    }

    let cancelled = false;
    let fadeTimer: number | undefined;

    const finishStartup = async () => {
      await new Promise<void>((resolve) => requestAnimationFrame(() => resolve()));
      if (cancelled || loadingScreenDismissedRef.current) return;

      const elapsed = performance.now() - loadingScreenStartedAtRef.current;
      const remainingMinimum = Math.max(0, LOADING_SCREEN_MIN_MS - elapsed);
      fadeTimer = window.setTimeout(() => {
        if (cancelled || loadingScreenDismissedRef.current) return;

        dismissLoadingScreen();
      }, remainingMinimum);
    };

    void finishStartup();
    return () => {
      cancelled = true;
      if (fadeTimer !== undefined) window.clearTimeout(fadeTimer);
    };
  }, [dismissLoadingScreen, libraryState.library, libraryState.status]);

  /*
   * A heartbeat, not the primary persistence path.
   *
   * Every change to the page or the player session is already written by the effect below, and
   * `beforeunload` catches a clean exit. All this adds is `positionSec` freshness for a restore
   * after a crash or a kill — so it ran every second, rebuilding the full queue and
   * history into a multi-megabyte object graph, stringifying it and writing it synchronously,
   * for a field that only has to be roughly right.
   *
   * At five seconds a hard kill costs at most five seconds of playback position. It writes the
   * position alone (`savePlaybackPosition`), not the session: rebuilding and stringifying the
   * queue and history every five seconds wrote tens of KB each time to say where playback was.
   */
  useEffect(() => {
    /*
     * Only while playing. The one field this heartbeat exists to keep fresh is `positionSec`,
     * and a paused or idle player's position does not move — so on a machine sitting on the
     * home page it was rebuilding and stringifying the queue and history, on a timer,
     * to write back a number that was already correct. The effect below still persists on
     * every real change, and the teardown here still writes on the way out.
     */
    const intervalId = playerState.status === "playing"
      ? window.setInterval(persistPlaybackPosition, SESSION_HEARTBEAT_MS)
      : 0;
    window.addEventListener("beforeunload", persistAppSession);
    return () => {
      window.clearInterval(intervalId);
      window.removeEventListener("beforeunload", persistAppSession);
      persistAppSession();
    };
  }, [persistAppSession, persistPlaybackPosition, playerState.status]);

  useEffect(() => {
    persistAppSession();
  }, [page, persistAppSession, playerSession]);

  useEffect(() => {
    const unlistenPromise = listen("main-window-recovery-reload", persistAppSession);
    return () => {
      void unlistenPromise.then((unlisten) => unlisten());
    };
  }, [persistAppSession]);

  useEffect(() => {
    sleepRecoveryLastTickRef.current = Date.now();

    const resetSleepTimerOnVisible = () => {
      if (document.visibilityState === "visible") {
        sleepRecoveryLastTickRef.current = Date.now();
      }
    };
    document.addEventListener("visibilitychange", resetSleepTimerOnVisible);

    const intervalId = window.setInterval(() => {
      const now = Date.now();
      const elapsed = now - sleepRecoveryLastTickRef.current;
      sleepRecoveryLastTickRef.current = now;

      if (
        elapsed < SLEEP_RECOVERY_TIMER_INTERVAL_MS + SLEEP_RECOVERY_TIMER_DRIFT_MS
        || document.visibilityState === "hidden"
        || sleepRecoveryReloadingRef.current
      ) {
        return;
      }

      sleepRecoveryReloadingRef.current = true;
      persistAppSession();
      window.location.reload();
    }, SLEEP_RECOVERY_TIMER_INTERVAL_MS);

    return () => {
      window.clearInterval(intervalId);
      document.removeEventListener("visibilitychange", resetSleepTimerOnVisible);
    };
  }, [persistAppSession]);

  const handleDeleteAllAppData = useCallback(async () => {
    sessionPersistenceDisabledRef.current = true;
    playerUIStore.setLyricsOpen(false);
    setIsSearchOpen(false);
    void player.pause();
    setPage({ view: "home" });
    setSettingsOpen(false);
    setSidebarWidth(240);
    setQueuePanelWidth(340);
    clearAppSession();

    const results = await Promise.allSettled([
      libraryController.signOut(),
      clearCache(),
      clearAppSettings(),
    ]);

    try {
      localStorage.clear();
    } catch {
      clearAppSession();
    }

    const failed = results.find((result) => result.status === "rejected");
    if (failed) {
      throw failed.reason;
    }
  }, []);

  useEffect(() => {
    if (!playerState.currentTrack && playerUIState.isLyricsOpen) {
      playerUIStore.setLyricsOpen(false);
    }
  }, [playerState.currentTrack, playerUIState.isLyricsOpen]);

  const handleNavigateAlbum = (album: Album) => {
    playerUIStore.setLyricsOpen(false);
    navigate({ view: "album", album });
  };

  /**
   * Opens the album a track belongs to.
   *
   * `Track.album` is a name with no id, so there is nothing to navigate to directly — the album
   * has to be looked up. The top album result for "<album> <artist>" is the right one in
   * practice; when nothing matches, the search page is a more useful landing place than an
   * error, since the query is already the thing the listener asked about.
   */
  const handleNavigateAlbumForTrack = async (track: Track) => {
    /*
     * The linked id, whenever the row carried one.
     *
     * Searching for "<album> <artist>" and taking the first hit is a guess, and it guesses
     * wrong on compilations, remasters and singles that share a title. The id names the album
     * outright — the header fills itself in once the page loads, the same way a pasted album
     * link is handled.
     */
    if (track.albumId) {
      handleNavigateAlbum({
        id: track.albumId,
        title: track.album ?? "Album",
        artist: track.artist ?? "",
        artworkUrl: track.artworkUrl,
      });
      return;
    }

    const query = [track.album, track.artist].filter(Boolean).join(" ").trim();
    if (!query) return;

    try {
      const results = await searchController.search(query);
      const album = results?.albums?.[0];
      if (album) {
        handleNavigateAlbum(album);
        return;
      }
    } catch (error) {
      logInternalWarn("App.handleNavigateAlbumForTrack failed", {
        trackId: track.id,
        error: error instanceof Error ? error.message : String(error),
      });
    }
    handleSearch(query);
  };

  const handleNavigateArtist = (artist: Artist) => {
    playerUIStore.setLyricsOpen(false);
    if (!artist.id) {
      const fallbackToSearch = () => handleSearch(artist.name);
      void searchController.search(artist.name)
        .then((results) => {
          const normalizedName = artist.name.trim().toLocaleLowerCase();
          const resolved = results.artists.find(
            (candidate) => candidate.name.trim().toLocaleLowerCase() === normalizedName,
          ) ?? results.artists.find((candidate) => {
            const candidateName = candidate.name.trim().toLocaleLowerCase();
            return candidateName.includes(normalizedName)
              || normalizedName.includes(candidateName);
          }) ?? results.artists[0];

          if (resolved) {
            handleNavigateArtist(resolved);
            return;
          }

          fallbackToSearch();
        })
        .catch(fallbackToSearch);
      return;
    }
    navigate({ view: "artist", artist, title: artist.name });
  };

  /*
   * Memoized because `PlayerBar` hangs its whole connectivity chain off this identity:
   * `updateConnectionState` → `checkConnection` → the effect that calls it on mount. A fresh
   * function each render re-ran that effect on every render, firing a live connectivity probe
   * each time — several per track change.
   */
  const handleConnectionRestored = useCallback(async () => {
    await libraryController.recoverConnection();
  }, []);

  const handleNavigatePlaylist = (playlist: Playlist) => {
    playerUIStore.setLyricsOpen(false);
    navigate({ view: "playlist", playlist });
  };

  const handleNavigateRelated = (track: Track) => {
    playerUIStore.setLyricsOpen(false);
    navigate({ view: "related", title: `Related to ${track.title}`, relatedTrack: track });
  };

  const handleSignIn = async () => {
    await libraryController.signIn();
    if (libraryController.getState().status !== "ready") return;

    playerUIStore.setLyricsOpen(false);
    navigate({ view: "home" });
  };

  /**
   * Opens a pasted YouTube link instead of searching for its text.
   *
   * Searching for a URL returns nothing useful, so a link in the search box is treated as a
   * request to go there. Anything that fails to resolve falls through to an ordinary search,
   * which is the behaviour without this.
   */
  const handleOpenLink = async (url: string): Promise<boolean> => {
    let resolved: Awaited<ReturnType<typeof libraryController.resolveLink>> = null;
    try {
      resolved = await libraryController.resolveLink(url);
    } catch {
      return false;
    }
    if (!resolved) return false;

    playerUIStore.setLyricsOpen(false);
    if (resolved.kind === "track") {
      await playerController.playTrackById(resolved.id);
      return true;
    }

    if (resolved.kind === "artist") {
      const page = await libraryController.getArtist(resolved.id);
      handleNavigateArtist(page.artist);
      return true;
    }

    if (resolved.kind === "album") {
      /*
       * The link carries an id and nothing else, so the header would read "Album" until the
       * page loaded. Fetching the tracks first — a request the album view then serves from
       * cache — supplies a real title and cover from the first row.
       */
      const stub: Album = { id: resolved.id, title: "Album", artist: "" };
      const tracks = await libraryController.getAlbumTracks(stub).catch(() => [] as Track[]);
      handleNavigateAlbum({
        ...stub,
        title: tracks[0]?.album ?? stub.title,
        artist: tracks[0]?.artist ?? "",
        artworkUrl: tracks[0]?.artworkUrl,
      });
      return true;
    }

    // ponytail: a playlist link has no title until its page loads, and the tracks do not
    // carry one. Fetch the playlist header here if the placeholder ever becomes a complaint.
    const saved = libraryController.getState().library?.playlists.find(
      (item) => item.id.replace(/^VL/, "") === resolved.id.replace(/^VL/, ""),
    );
    handleNavigatePlaylist(saved ?? {
      id: resolved.id,
      title: "Playlist",
      owner: "",
    });
    return true;
  };

  const handleSearch = (query: string) => {
    playerUIStore.setLyricsOpen(false);

    if (looksLikeYouTubeLink(query)) {
      void handleOpenLink(query).then((opened) => {
        // Not a link the app can open after all — fall back to searching for the text, so a
        // paste that resolves to nothing still does something.
        if (!opened) runSearch(query);
      });
      return;
    }

    runSearch(query);
  };

  const runSearch = (query: string) => {
    navigate({
      view: "search",
      title: query,
      searchQuery: query,
      searchResults: [],
      mixedSearchResults: { artists: [], tracks: [], albums: [], playlists: [] },
      searchLoading: true,
    });

    const applySearchResults = (results: SearchResults) => {
      updateSearchPage(query, {
        view: "search",
        title: query,
        searchQuery: query,
        searchResults: results.tracks,
        mixedSearchResults: results,
        searchLoading: false,
      });
    };

    void searchController.search(query, applySearchResults)
      .then(applySearchResults)
      .catch(() => {
        updateSearchPage(query, {
          view: "search",
          title: query,
          searchQuery: query,
          searchResults: [],
          mixedSearchResults: { artists: [], tracks: [], albums: [], playlists: [] },
          searchLoading: false,
        });
      });
  };

  const handleOpenSettings = () => {
    playerUIStore.setLyricsOpen(false);
    setSettingsOpen(true);
  };

  const handleOpenHistory = () => {
    playerUIStore.setLyricsOpen(false);
    navigate({ view: "history", title: "History" });
  };

  const handleOpenLibrary = () => {
    playerUIStore.setLyricsOpen(false);
    navigate({ view: "library", title: "Library" });
  };

  const handleOpenBrowse = (browseTab?: string) => {
    playerUIStore.setLyricsOpen(false);
    navigate({ view: "browse", title: "Browse", browseTab });
  };

  const handlePlayTrack = (track: Track) => {
    void playerController.playTrackById(track.id, [track], true);
  };

  const handleToggleLyrics = () => {
    if (playerUIState.isLyricsOpen) {
      playerUIStore.setLyricsOpen(false);
      return;
    }

    playerUIStore.setLyricsOpen(true);
  };

  const handleToggleQueue = () => {
    // Toggle asynchronously to avoid triggering synchronous store updates
    // during React commit phase which can cause "Maximum update depth".
    setTimeout(() => setIsQueuePanelOpen(!isQueuePanelOpen), 0);
  };

  useEffect(() => {
    const preventTabFocusTraversal = (event: KeyboardEvent) => {
      if (event.key !== "Tab") return;

      event.preventDefault();
      if (document.activeElement instanceof HTMLElement) {
        document.activeElement.blur();
      }
    };

    window.addEventListener("keydown", preventTabFocusTraversal);
    return () => window.removeEventListener("keydown", preventTabFocusTraversal);
  }, []);

  useEffect(() => {
    const isTextEntry = (target: EventTarget | null) => {
      return target instanceof Element
        && target.closest(
          'input, textarea, select, [contenteditable]:not([contenteditable="false"])',
        ) !== null;
    };

    const handleMouseNavigation = (event: MouseEvent) => {
      if (
        event.button !== MOUSE_BACK_BUTTON
        && event.button !== MOUSE_FORWARD_BUTTON
      ) {
        return;
      }
      if (isTextEntry(event.target)) return;

      if (event.button === MOUSE_BACK_BUTTON) {
        if (isSearchOpen && !settingsOpen) {
          event.preventDefault();
          setIsSearchOpen(false);
          return;
        }
        if (canNavigateBack) {
          event.preventDefault();
          handleNavigateBack();
        }
        return;
      }

      if (canNavigateForward) {
        event.preventDefault();
        handleNavigateForward();
      }
    };

    const preventAuxNavigation = (event: MouseEvent) => {
      if (
        event.button === MOUSE_BACK_BUTTON
        || event.button === MOUSE_FORWARD_BUTTON
      ) {
        event.preventDefault();
      }
    };

    window.addEventListener("mousedown", handleMouseNavigation);
    window.addEventListener("auxclick", preventAuxNavigation);
    return () => {
      window.removeEventListener("mousedown", handleMouseNavigation);
      window.removeEventListener("auxclick", preventAuxNavigation);
    };
  }, [
    canNavigateBack,
    canNavigateForward,
    handleNavigateBack,
    handleNavigateForward,
    isSearchOpen,
    settingsOpen,
  ]);

  useEffect(() => {
    const isTextEntry = (target: EventTarget | null) => {
      return target instanceof Element
        && target.closest(
          'input, textarea, select, [contenteditable]:not([contenteditable="false"])',
        ) !== null;
    };

    const handleShortcut = (event: KeyboardEvent) => {
      if (event.repeat) return;
      if (event.defaultPrevented) return;
      if (isTextEntry(event.target)) return;

      if (eventMatchesShortcut(event, keyboardShortcuts.search) && !settingsOpen) {
        event.preventDefault();
        setIsSearchOpen(!isSearchOpen);
        return;
      }

      if (eventMatchesShortcut(event, keyboardShortcuts.navigateBack)) {
        if (isSearchOpen && !settingsOpen) {
          event.preventDefault();
          setIsSearchOpen(false);
          return;
        }
        if (canNavigateBack) {
          event.preventDefault();
          handleNavigateBack();
        }
        return;
      }

      if (eventMatchesShortcut(event, keyboardShortcuts.navigateForward)) {
        if (canNavigateForward) {
          event.preventDefault();
          handleNavigateForward();
        }
        return;
      }

      if (
        eventMatchesShortcut(event, keyboardShortcuts.playPause)
        && playerState.currentTrack
        && playerState.status !== "loading"
      ) {
        event.preventDefault();
        event.stopPropagation();
        if (event.target instanceof HTMLElement) {
          event.target.blur();
        }
        void playerController.togglePlayPause();
        return;
      }

      if (
        eventMatchesShortcut(event, keyboardShortcuts.mute)
        && playerState.currentTrack
        && playerState.status !== "loading"
      ) {
        event.preventDefault();
        void playerController.toggleMute();
        return;
      }

      if (
        eventMatchesShortcut(event, keyboardShortcuts.previousTrack)
        && playerState.currentTrack
        && playerState.status !== "loading"
      ) {
        event.preventDefault();
        void playerController.skipToPrevious();
        return;
      }

      if (
        eventMatchesShortcut(event, keyboardShortcuts.nextTrack)
        && playerState.currentTrack
        && playerState.status !== "loading"
      ) {
        event.preventDefault();
        void playerController.skipToNext();
      }
    };

    window.addEventListener("keydown", handleShortcut, true);
    return () => window.removeEventListener("keydown", handleShortcut, true);
  }, [
    canNavigateBack,
    canNavigateForward,
    handleNavigateBack,
    handleNavigateForward,
    isSearchOpen,
    keyboardShortcuts,
    playerState.currentTrack,
    playerState.status,
    settingsOpen,
  ]);


  return (
    <MotionConfig reducedMotion={reduceMotion ? "always" : "user"}>
    <ArtistNavigationProvider onNavigate={handleNavigateArtist}>
    <TrackContextMenuProvider
      libraryController={libraryController}
      onOpenRelated={handleNavigateRelated}
      onOpenAlbum={(track) => void handleNavigateAlbumForTrack(track)}
    >
    <PlaylistContextMenuProvider libraryController={libraryController}>
    {/*
      `ring-inset` is load-bearing: the window is transparent, so an outward ring would be
      drawn into nothing and clipped.
    */}
    <div className="relative flex h-screen flex-col overflow-hidden rounded-[var(--window-radius)] border border-border ring-1 ring-inset ring-[var(--window-edge)]">
      {/* Dropped entirely in full-screen lyrics, not just visually hidden */}
      {!playerUIState.isLyricsFullscreen && (
      <TitleBar
        sidebarWidth={sidebarWidth}
        isHomeActive={page.view === "home" && !settingsOpen}
        onNavigateHome={handleNavigateHome}
        onOpenSettings={handleOpenSettings}
        onOpenDownloads={() => handleOpenBrowse("downloads")}
      />
      )}

      <div className="flex min-h-0 flex-1 flex-col">

        <Layout
          sidebarWidth={sidebarWidth}
          onSidebarWidthChange={setSidebarWidth}
          onNavigateAlbum={handleNavigateAlbum}
          onNavigatePlaylist={handleNavigatePlaylist}
          showSearchBar={!settingsOpen && !playerUIState.isLyricsOpen}
          onOpenSearch={() => setIsSearchOpen(true)}
          canGoBack={canNavigateBack}
          canGoForward={canNavigateForward}
          onNavigateBack={handleNavigateBack}
          onNavigateForward={handleNavigateForward}
          fullBleedContent={playerUIState.isLyricsOpen}
          hideSidebar={playerUIState.isLyricsFullscreen}
          showTransientScrollbar={
            !playerUIState.isLyricsOpen
            && !settingsOpen
            && (page.view === "playlist" || page.view === "album")
          }
          rightPanelWidth={isQueuePanelCollapsed ? COLLAPSED_QUEUE_WIDTH : queuePanelWidth}
          onRightPanelWidthChange={isQueuePanelCollapsed ? undefined : setQueuePanelWidth}
          scrollKey={activeViewKey}
          /*
            Bound straight to `isQueuePanelOpen`, not a delayed mirror of it: `AnimatePresence`
            in Layout already keeps the last-rendered panel mounted for the whole exit
            animation on its own. An extra `showQueueMounted` state used to sit between this
            and the panel, unmounting it 200ms after close on a hardcoded guess — which meant
            the close animation didn't start until that guess elapsed, then had to play out a
            spring on top of it. Removing the mirror is what makes closing start immediately.
          */
          rightPanel={isQueuePanelOpen ? (
            <QueuePanel onClose={() => setIsQueuePanelOpen(false)} />
          ) : undefined}
        >
          {/*
            Keyed on the view so navigating away clears a caught error: a page that failed on
            one album's malformed response must not stay broken for the next one. The player
            bar and sidebar sit outside, so a dead page still leaves playback controllable.
          */}
          <ErrorBoundary
            key={`boundary:${activeViewKey}`}
            label="This page"
            onDismiss={canNavigateBack ? handleNavigateBack : undefined}
          >
          {playerUIState.isLyricsOpen && !settingsOpen ? (
            <LyricsView onClose={() => playerUIStore.setLyricsOpen(false)} />
          ) : (
          <div key={activeViewKey} className="min-h-0 flex-1">
            {settingsOpen && (
              <SettingsPage
                libraryController={libraryController}
                libraryState={libraryState}
                onSignIn={handleSignIn}
                onClose={() => setSettingsOpen(false)}
                onDeleteAllAppData={handleDeleteAllAppData}
              />
            )}
            {!settingsOpen && page.view === "home" && (
              <HomePage
                playerController={playerController}
                libraryController={libraryController}
                libraryState={libraryState}
                searchController={searchController}
                onSignIn={handleSignIn}
                destinations={{
                  onOpenLibrary: handleOpenLibrary,
                  onOpenBrowse: () => handleOpenBrowse(),
                  onOpenHistory: handleOpenHistory,
                  onOpenDownloads: () => handleOpenBrowse("downloads"),
                }}
              />
            )}
            {!settingsOpen && page.view === "album" && (
              <AlbumView
                album={page.album}
                playerController={playerController}
                libraryController={libraryController}
              />
            )}
            {!settingsOpen && page.view === "artist" && (
              <ArtistView
                artist={page.artist}
                playerController={playerController}
                libraryController={libraryController}
                onOpenAlbum={handleNavigateAlbum}
                onOpenPlaylist={handleNavigatePlaylist}
              />
            )}
            {!settingsOpen && page.view === "playlist" && (
              <PlaylistView
                playlist={page.playlist}
                playerController={playerController}
                libraryController={libraryController}
              />
            )}
            {!settingsOpen && page.view === "related" && page.relatedTrack && (
              <RelatedPage
                track={page.relatedTrack}
                playerController={playerController}
                onOpenAlbum={handleNavigateAlbum}
                onOpenArtist={(artist) => handleNavigateArtist(artist)}
                onOpenPlaylist={handleNavigatePlaylist}
              />
            )}
            {!settingsOpen && page.view === "search" && (
                <SearchResultsPage
                query={page.searchQuery ?? ""}
                results={page.mixedSearchResults ?? {
                  artists: [],
                  tracks: page.searchResults ?? [],
                  albums: [],
                  playlists: [],
                }}
                isLoading={page.searchLoading ?? false}
                  playerController={playerController}
                onPlayTrack={handlePlayTrack}
                onOpenArtist={(artist) => handleNavigateArtist(artist)}
                onOpenAlbum={handleNavigateAlbum}
                onOpenPlaylist={handleNavigatePlaylist}
                />
            )}
            {!settingsOpen && page.view === "library" && (
              <LibraryPage
                libraryState={libraryState}
                playerController={playerController}
                onOpenAlbum={handleNavigateAlbum}
                onOpenArtist={(artist) => handleNavigateArtist(artist)}
                onOpenPlaylist={handleNavigatePlaylist}
              />
            )}
            {!settingsOpen && page.view === "browse" && (
              <BrowsePage
                key={page.browseTab ?? "explore"}
                initialTab={(page.browseTab ?? "explore") as never}
                playerController={playerController}
                libraryController={libraryController}
                onOpenAlbum={handleNavigateAlbum}
                onOpenArtist={(artist) => handleNavigateArtist(artist)}
                onOpenPlaylist={handleNavigatePlaylist}
              />
            )}
            {!settingsOpen && page.view === "history" && (
              <HistoryPage playerController={playerController} />
            )}
          </div>
          )}
          </ErrorBoundary>
        </Layout>
      </div>

      {/*
        Fullscreen lyrics: the bar becomes a bottom overlay instead of a row that permanently
        eats height, hidden until the pointer reaches the bottom edge — same reveal-on-hover
        contract as a fullscreen video player's controls. `group/immersive-playerbar` is a
        different name than PlayerBar's own `group/playerbar` (used internally for its icon
        fade-in), so nesting them here doesn't make PlayerBar's hover styling fire early.
      */}
      <div
        className={cn(
          "group/immersive-playerbar",
          playerUIState.isLyricsFullscreen && "absolute inset-x-0 bottom-0 z-40",
        )}
      >
        {playerUIState.isLyricsFullscreen && (
          /*
           * Translating the bar away moves its hitbox with it, so there is nothing left under
           * the pointer to hover — this stand-in strip is what the reveal actually triggers
           * on. Kept to the literal screen edge (8px) rather than a comfortable target size:
           * this sits above the lyrics footer's own buttons (offset controls, source panel),
           * so anything taller would eat clicks meant for them before the bar is revealed. A
           * mouse run to the physical bottom of the window hits it regardless of how thin it
           * is — that's the same trick fullscreen video controls rely on.
           */
          <div className="absolute inset-x-0 bottom-0 h-2" aria-hidden="true" />
        )}
        <div
          className={cn(
            playerUIState.isLyricsFullscreen &&
              "translate-y-full transition-transform duration-300 ease-out group-hover/immersive-playerbar:translate-y-0 group-focus-within/immersive-playerbar:translate-y-0",
          )}
        >
          {/* Its own boundary: the player bar is the one region whose loss ends the session —
              audio keeps playing but nothing can pause or skip it. */}
          <ErrorBoundary label="Playback controls">
            <PlayerBar
              onToggleLyrics={handleToggleLyrics}
              onToggleQueue={handleToggleQueue}
              isQueueOpen={isQueuePanelOpen}
              onConnectionRestored={handleConnectionRestored}
            />
          </ErrorBoundary>
        </div>
      </div>
      <SearchOverlay
        isOpen={isSearchOpen && !settingsOpen}
        searchController={searchController}
        albums={libraryState.library?.albums ?? []}
        playlists={libraryState.library?.playlists ?? []}
        onClose={() => setIsSearchOpen(false)}
        onSubmit={handleSearch}
        onPlayTrack={handlePlayTrack}
        onOpenAlbum={handleNavigateAlbum}
        onOpenArtist={(artist) => handleNavigateArtist(artist)}
        onOpenPlaylist={handleNavigatePlaylist}
      />
      {loadingScreenState !== "hidden" && (
        <AppLoadingScreen isLeaving={loadingScreenState === "leaving"} />
      )}
      {/*
        Mounted only while a sign-in is running: `signInProgress` is null at every other moment,
        so the overlay and its animation cost nothing for the whole rest of the session.
      */}
      <AnimatePresence>
        {libraryState.authProgress && (
          <AuthOverlay
            progress={libraryState.authProgress}
            onCancel={() => void libraryController.cancelSignIn()}
          />
        )}
      </AnimatePresence>
    </div>
    </PlaylistContextMenuProvider>
    </TrackContextMenuProvider>
    </ArtistNavigationProvider>
    </MotionConfig>
  );
}
