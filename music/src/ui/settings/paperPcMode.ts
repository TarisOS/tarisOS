// Modified for TarisOS (Taris Music) by George Dobreff ("Witcher") and contributors, 2026.
import { useSyncExternalStore } from "react";
import {
  hydrateLocalBooleanSetting,
  readLocalBooleanSetting,
  writeLocalBooleanSetting,
} from "../../internal/durableLocalSetting";

const STORAGE_KEY = "paper-pc-mode";
const CHANGE_EVENT = "paper-pc-mode-change";
/**
 * On unless switched off (TarisOS). Every effect it turns off costs GPU and CPU time on every
 * frame it is shown, for looks alone, on what is usually a laptop on battery. Only reaches an
 * install that has never stored the setting: the first launch of any version stores whatever
 * it read, so an existing install keeps the default it started with.
 */
const DEFAULT_ENABLED = true;

/*
 * Cached for the same reason as the render-effects snapshot: `useReduceMotion` reads this, and
 * it is called once per album card. `useSyncExternalStore` asks for the snapshot more than
 * once per render, so uncached this was a `localStorage.getItem` per card per render for a
 * value that changes when someone opens Settings.
 */
let cached: boolean | null = null;

export function readPaperPcMode() {
  if (cached === null) cached = readLocalBooleanSetting(STORAGE_KEY, DEFAULT_ENABLED);
  return cached;
}

function invalidate() {
  cached = null;
}

/**
 * Drops the cache so the next read goes back to storage.
 *
 * Exported for `hydrateRenderEffects`, which reads this flag to decide a one-time migration and
 * runs alongside `hydratePaperPcMode` rather than after it. Without this it could read a value
 * primed from local storage before the durable store had finished correcting it.
 */
export function invalidatePaperPcModeCache(): void {
  invalidate();
}

// At module scope, so the cache is already stale before any React subscriber runs.
if (typeof window !== "undefined") {
  window.addEventListener(CHANGE_EVENT, invalidate);
  window.addEventListener("storage", invalidate);
}

function subscribe(callback: () => void) {
  window.addEventListener(CHANGE_EVENT, callback);
  window.addEventListener("storage", callback);

  return () => {
    window.removeEventListener(CHANGE_EVENT, callback);
    window.removeEventListener("storage", callback);
  };
}

export function applyPaperPcMode(enabled = readPaperPcMode()) {
  document.documentElement.toggleAttribute("data-paper-pc", enabled);
}

export async function hydratePaperPcMode() {
  await hydrateLocalBooleanSetting(STORAGE_KEY, DEFAULT_ENABLED, CHANGE_EVENT, applyPaperPcMode);
  invalidate();
}

export function setPaperPcMode(enabled: boolean) {
  // Explicit rather than relying on the write helper's event: this cache must not depend on
  // what another module chooses to dispatch.
  cached = enabled;
  writeLocalBooleanSetting(STORAGE_KEY, enabled, CHANGE_EVENT);
  window.location.reload();
}

export function usePaperPcMode() {
  return useSyncExternalStore(subscribe, readPaperPcMode, () => DEFAULT_ENABLED);
}
