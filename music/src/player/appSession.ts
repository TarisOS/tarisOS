// Modified for TarisOS (Taris Music) by George Dobreff ("Witcher") and contributors, 2026.
import type { Page } from "../ui/types/page";
import type { PlayerSession } from "./PlayerController";

const STORAGE_KEY = "taris-music.app-session";

export interface AppSession {
  version: 2;
  page: Page;
  player: PlayerSession;
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

export function loadAppSession(): AppSession | null {
  try {
    const parsed = JSON.parse(localStorage.getItem(STORAGE_KEY) ?? "null") as AppSession | null;
    if (parsed?.version !== 2 || !parsed.page || !parsed.player) {
      return null;
    }
    return restoreWithoutAutoplay(parsed);
  } catch {
    return null;
  }
}

/**
 * The payload last written, so an unchanged session costs a comparison rather than a write.
 *
 * The session is persisted from three places — a heartbeat, an effect watching the page and
 * player session, and `beforeunload` — and most of those fire when nothing that actually gets
 * persisted has moved. `localStorage.setItem` is synchronous and disk-backed, so skipping the
 * no-op writes is worth more than the string comparison costs.
 */
let lastWrittenSession: string | null = null;

export function saveAppSession(session: AppSession): void {
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
    // Or the next save would match the cleared value and decline to rewrite it.
    lastWrittenSession = null;
  } catch {
    // Persistence failure should not interrupt a full reset.
  }
}
