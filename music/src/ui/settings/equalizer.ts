// Modified for TarisOS (Taris Music) by George Dobreff ("Witcher") and contributors, 2026.
import { useSyncExternalStore } from "react";
import { invoke } from "@tauri-apps/api/core";
import {
  hydrateLocalBooleanSetting,
  hydrateLocalJsonSetting,
  readLocalBooleanSetting,
  readLocalJsonSetting,
  writeLocalBooleanSetting,
  writeLocalJsonSetting,
} from "../../internal/durableLocalSetting";
import { logInternalWarn } from "../../internal/logging";

/**
 * Ten-band graphic equaliser.
 *
 * The gains live here; the filtering happens in Rust, between the decoder and the deck. That is
 * also why this only works on the Rust engine — the IFrame player never exposes its samples, and
 * a track that fell back to it plays unequalised however these sliders are set.
 *
 * Rust holds the current values in process-global state, so they survive track changes and apply
 * to both decks during a crossfade. They do *not* survive a restart, which is why `hydrate` ends
 * by pushing them back down.
 */
export const EQUALIZER_BANDS_HZ = [31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000] as const;

/** Matches `MAX_GAIN_DB` in `equalizer.rs`, which clamps to the same range on the way in. */
export const EQUALIZER_MAX_DB = 12;

export type EqualizerSettings = {
  preampDb: number;
  bandsDb: number[];
};

export const EQUALIZER_FLAT: EqualizerSettings = {
  preampDb: 0,
  bandsDb: EQUALIZER_BANDS_HZ.map(() => 0),
};

/*
 * Presets carry a negative preamp wherever they boost.
 *
 * A normalised track has very little headroom left, so lifting four bands by 6 dB without
 * trimming the input hits the limiter and what comes out is compression rather than tone. Each
 * preset gives back roughly what its largest boost takes.
 */
export const EQUALIZER_PRESETS: ReadonlyArray<{ name: string; settings: EqualizerSettings }> = [
  { name: "Flat", settings: EQUALIZER_FLAT },
  {
    name: "Bass",
    settings: { preampDb: -4, bandsDb: [6, 5, 4, 2, 0, 0, 0, 0, 0, 0] },
  },
  {
    name: "Vocal",
    settings: { preampDb: -3, bandsDb: [-2, -2, -1, 1, 3, 4, 3, 1, 0, 0] },
  },
  {
    name: "Treble",
    settings: { preampDb: -3, bandsDb: [0, 0, 0, 0, 0, 1, 2, 4, 5, 5] },
  },
];

/**
 * Which preset, if any, matches the current curve exactly.
 *
 * Shared by the full settings page and the player-bar mini equaliser so "which chip is lit"
 * cannot drift into two slightly different definitions of "matches."
 */
export function activeEqualizerPreset(
  settings: EqualizerSettings,
): (typeof EQUALIZER_PRESETS)[number] | undefined {
  return EQUALIZER_PRESETS.find(
    (preset) =>
      preset.settings.preampDb === settings.preampDb
      && preset.settings.bandsDb.every((gain, index) => gain === settings.bandsDb[index]),
  );
}

const STORAGE_KEY = "equalizer-v1";
const CHANGE_EVENT = "equalizer-change";

/*
 * On/off, kept separate from the curve itself.
 *
 * The curve is what the sliders shape; the switch is whether it is currently being listened to.
 * Folding it into `EqualizerSettings` would mean flattening the bands to turn it off and
 * remembering them somewhere to turn it back on — this way the sliders keep the user's shape the
 * whole time, on or off, exactly like a hardware EQ's bypass switch.
 */
const ENABLED_STORAGE_KEY = "equalizer-enabled-v1";
const ENABLED_CHANGE_EVENT = "equalizer-enabled-change";

function isEqualizerSettings(value: unknown): value is EqualizerSettings {
  if (typeof value !== "object" || value === null) return false;
  const candidate = value as EqualizerSettings;
  return typeof candidate.preampDb === "number"
    && Array.isArray(candidate.bandsDb)
    && candidate.bandsDb.length === EQUALIZER_BANDS_HZ.length
    && candidate.bandsDb.every((gain) => typeof gain === "number");
}

/*
 * Cached because the settings page reads this on every render of every slider, and the snapshot
 * handed to `useSyncExternalStore` has to be reference-stable or React re-renders forever.
 */
let cached: EqualizerSettings | null = null;
let enabledCached: boolean | null = null;

function readSettings(): EqualizerSettings {
  if (cached === null) {
    cached = readLocalJsonSetting(STORAGE_KEY, isEqualizerSettings) ?? EQUALIZER_FLAT;
  }
  return cached;
}

/** True when every band and the preamp are at zero, so nothing is being changed. */
export function isEqualizerFlat(settings: EqualizerSettings): boolean {
  return settings.preampDb === 0 && settings.bandsDb.every((gain) => gain === 0);
}

/** The bypass switch — independent of the curve. See `ENABLED_STORAGE_KEY`. */
export function isEqualizerEnabled(): boolean {
  if (enabledCached === null) {
    enabledCached = readLocalBooleanSetting(ENABLED_STORAGE_KEY, false);
  }
  return enabledCached;
}

export function setEqualizerEnabled(enabled: boolean): void {
  enabledCached = enabled;
  writeLocalBooleanSetting(ENABLED_STORAGE_KEY, enabled, ENABLED_CHANGE_EVENT);
  // Re-push under the new switch state — flat if this just turned it off, the stored curve if
  // it just turned back on.
  push(readSettings());
}

/// Rust has no notion of "off": it only ever sees a curve, flat or not. The switch lives here,
/// entirely on the frontend, by choosing what to push rather than sending the switch itself.
function push(settings: EqualizerSettings): void {
  const applied = isEqualizerEnabled() ? settings : EQUALIZER_FLAT;
  void invoke("native_audio_set_equalizer", {
    preampDb: applied.preampDb,
    bandsDb: applied.bandsDb,
  }).catch((error: unknown) => {
    logInternalWarn("Equalizer push failed", {
      error: error instanceof Error ? error.message : String(error),
    });
  });
}

export function setEqualizer(settings: EqualizerSettings): void {
  const clamped: EqualizerSettings = {
    preampDb: clamp(settings.preampDb),
    bandsDb: settings.bandsDb.map(clamp),
  };
  cached = clamped;
  writeLocalJsonSetting(STORAGE_KEY, clamped);
  // Before the event, so a component that reads back on the change already sees it applied.
  push(clamped);
  window.dispatchEvent(new Event(CHANGE_EVENT));
}

function clamp(gain: number): number {
  if (!Number.isFinite(gain)) return 0;
  return Math.min(EQUALIZER_MAX_DB, Math.max(-EQUALIZER_MAX_DB, gain));
}

function subscribe(callback: () => void) {
  window.addEventListener(CHANGE_EVENT, callback);
  window.addEventListener("storage", callback);
  return () => {
    window.removeEventListener(CHANGE_EVENT, callback);
    window.removeEventListener("storage", callback);
  };
}

function subscribeEnabled(callback: () => void) {
  window.addEventListener(ENABLED_CHANGE_EVENT, callback);
  window.addEventListener("storage", callback);
  return () => {
    window.removeEventListener(ENABLED_CHANGE_EVENT, callback);
    window.removeEventListener("storage", callback);
  };
}

if (typeof window !== "undefined") {
  window.addEventListener("storage", () => {
    cached = null;
    enabledCached = null;
  });
}

export async function hydrateEqualizer(): Promise<void> {
  await hydrateLocalJsonSetting(STORAGE_KEY, isEqualizerSettings);
  await hydrateLocalBooleanSetting(ENABLED_STORAGE_KEY, false, ENABLED_CHANGE_EVENT);
  cached = null;
  enabledCached = null;
  /*
   * Rust starts flat every launch — the values are process state, not a file — so the stored
   * settings have to be pushed down or the equaliser silently does nothing until the user
   * touches a slider.
   */
  push(readSettings());
  window.dispatchEvent(new Event(CHANGE_EVENT));
}

export function useEqualizer(): EqualizerSettings {
  return useSyncExternalStore(subscribe, readSettings, () => EQUALIZER_FLAT);
}

export function useEqualizerEnabled(): boolean {
  return useSyncExternalStore(subscribeEnabled, isEqualizerEnabled, () => false);
}
