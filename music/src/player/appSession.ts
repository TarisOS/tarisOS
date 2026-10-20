// Modified for TarisOS (Taris Music) by George Dobreff ("Witcher") and contributors, 2026.
import type { Page } from "../ui/types/page";
import type { PlayerSession } from "./PlayerController";

const STORAGE_KEY = "taris-music.app-session";
/**
 * The playback position on its own, so keeping it fresh while playing writes a few dozen bytes
 * instead of the whole session — the queue and history make that tens of KB, and more with a
 * long queue. Every full save writes it too, so it is always the newest position.
 */
const POSITION_KEY = "taris-music.app-session.position";

export interface AppSession {
  version: 2;
  page: Page;
  player: PlayerSession;
}

interface SavedPosition {
  trackId: string;
  positionSec: number;
}

/** Playback always comes back paused. */
function restoreWithoutAutoplay(session: AppSession): AppSession {
  return {
    ...session,
    player: {
      ...session.player,
      status: session.player.status === "playing" ? "paused" : session.player.status,
    },
  };
}

/** The newest saved position, when it belongs to the session's current track. */
function withSavedPosition(session: AppSession): AppSession {
  try {
    const saved = JSON.parse(localStorage.getItem(POSITION_KEY) ?? "null") as SavedPosition | null;
    if (
      !saved
      || saved.trackId !== session.player.currentTrack?.id
      || typeof saved.positionSec !== "number"
    ) {
      return session;
    }
    return { ...session, player: { ...session.player, positionSec: saved.positionSec } };
  } catch {
    return session;
  }
}

export function loadAppSession(): AppSession | null {
  try {
    const parsed = JSON.parse(localStorage.getItem(STORAGE_KEY) ?? "null") as AppSession | null;
    if (parsed?.version !== 2 || !parsed.page || !parsed.player) {
      return null;
    }
    return restoreWithoutAutoplay(withSavedPosition(parsed));
  } catch {
    return null;
  }
}

/** The position last written, for the same reason as `lastWrittenSession` below. */
let lastWrittenPosition: string | null = null;

/**
 * Writes where playback is. Used by the heartbeat while playing; nothing else in the session
 * moves on its own, and every real change still writes the whole session.
 */
export function savePlaybackPosition(
  trackId: string | null | undefined,
  positionSec: number,
): void {
  if (!trackId) return;
  try {
    const position: SavedPosition = { trackId, positionSec };
    const payload = JSON.stringify(position);
    if (payload === lastWrittenPosition) return;
    localStorage.setItem(POSITION_KEY, payload);
    lastWrittenPosition = payload;
  } catch {
    // Persistence failure should not interrupt playback.
  }
}

/**
 * The payload last written, so an unchanged session costs a comparison rather than a write.
 *
 * The session is persisted from several places — the effect watching the page and player
 * session, `beforeunload`, the end of each playing stretch and the reload paths — and most of
 * those fire when nothing that actually gets persisted has moved. `localStorage.setItem` is
 * synchronous and disk-backed, so skipping the no-op writes is worth more than the string
 * comparison costs.
 */
let lastWrittenSession: string | null = null;

export function saveAppSession(session: AppSession): void {
  // Whatever the comparison below decides: the position key must hold the newest position.
  savePlaybackPosition(session.player.currentTrack?.id, session.player.positionSec);
  try {
    const payload = JSON.stringify(session);
    if (payload === lastWrittenSession) return;
    localStorage.setItem(STORAGE_KEY, payload);
    lastWrittenSession = payload;
  } catch {
    // Persistence failure should not interrupt playback.
  }
}

export function clearAppSession(): void {
  try {
    localStorage.removeItem(STORAGE_KEY);
    localStorage.removeItem(POSITION_KEY);
    // Or the next save would match the cleared value and decline to rewrite it.
    lastWrittenSession = null;
    lastWrittenPosition = null;
  } catch {
    // Persistence failure should not interrupt a full reset.
  }
}
