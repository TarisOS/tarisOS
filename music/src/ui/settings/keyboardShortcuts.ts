// Modified for TarisOS (Taris Music) by George Dobreff ("Witcher") and contributors, 2026.
import { useSyncExternalStore } from "react";
import { getAppSetting, setAppSetting } from "../../internal/appSettings";

export type KeyboardShortcutAction =
  | "playPause"
  | "mute"
  | "previousTrack"
  | "nextTrack"
  | "search"
  | "navigateBack"
  | "navigateForward";

export interface KeyboardShortcut {
  code: string;
  key: string;
  /** Ctrl */
  primary?: boolean;
  meta?: boolean;
  alt?: boolean;
  shift?: boolean;
}

export type KeyboardShortcutMap = Record<KeyboardShortcutAction, KeyboardShortcut | null>;

export const KEYBOARD_SHORTCUTS_STORAGE_KEY = "keyboard-shortcuts";
const CHANGE_EVENT = "keyboard-shortcuts-change";
let cachedKeyboardShortcuts: KeyboardShortcutMap | null = null;

export const KEYBOARD_SHORTCUT_ACTIONS: Array<{
  id: KeyboardShortcutAction;
  label: string;
  description: string;
}> = [
  {
    id: "playPause",
    label: "Play / pause",
    description: "Toggle playback for the current track.",
  },
  {
    id: "mute",
    label: "Mute / unmute",
    description: "Toggle player audio.",
  },
  {
    id: "previousTrack",
    label: "Previous track",
    description: "Go back to the previous track.",
  },
  {
    id: "nextTrack",
    label: "Next track",
    description: "Skip to the next track.",
  },
  {
    id: "search",
    label: "Search",
    description: "Open or close search.",
  },
  {
    id: "navigateBack",
    label: "Go back",
    description: "Go back.",
  },
  {
    id: "navigateForward",
    label: "Go forward",
    description: "Go forward.",
  },
];

export const DEFAULT_KEYBOARD_SHORTCUTS: KeyboardShortcutMap = {
  playPause: { code: "Space", key: " " },
  mute: { code: "KeyM", key: "m" },
  previousTrack: { code: "ArrowLeft", key: "ArrowLeft", primary: true },
  nextTrack: { code: "ArrowRight", key: "ArrowRight", primary: true },
  search: { code: "Space", key: " ", primary: true },
  navigateBack: { code: "ArrowLeft", key: "ArrowLeft", alt: true },
  navigateForward: { code: "ArrowRight", key: "ArrowRight", alt: true },
};

const modifierCodes = new Set([
  "AltLeft",
  "AltRight",
  "ControlLeft",
  "ControlRight",
  "MetaLeft",
  "MetaRight",
  "ShiftLeft",
  "ShiftRight",
]);

function isKeyboardShortcut(value: unknown): value is KeyboardShortcut {
  if (typeof value !== "object" || value === null) return false;
  const shortcut = value as KeyboardShortcut;
  return (
    typeof shortcut.code === "string"
    && typeof shortcut.key === "string"
    && (shortcut.primary === undefined || typeof shortcut.primary === "boolean")
    && (shortcut.meta === undefined || typeof shortcut.meta === "boolean")
    && (shortcut.alt === undefined || typeof shortcut.alt === "boolean")
    && (shortcut.shift === undefined || typeof shortcut.shift === "boolean")
  );
}

function isShortcutMap(value: unknown): value is Partial<KeyboardShortcutMap> {
  if (typeof value !== "object" || value === null) return false;
  return KEYBOARD_SHORTCUT_ACTIONS.every(({ id }) => {
    const shortcut = (value as Partial<KeyboardShortcutMap>)[id];
    return shortcut === undefined || shortcut === null || isKeyboardShortcut(shortcut);
  });
}

function normalizeShortcut(shortcut: KeyboardShortcut): KeyboardShortcut {
  const next: KeyboardShortcut = {
    code: shortcut.code,
    key: shortcut.key,
  };
  if (shortcut.primary) next.primary = true;
  if (shortcut.meta) next.meta = true;
  if (shortcut.alt) next.alt = true;
  if (shortcut.shift) next.shift = true;
  return next;
}

function normalizeShortcutMap(value: Partial<KeyboardShortcutMap>): KeyboardShortcutMap {
  const next = { ...DEFAULT_KEYBOARD_SHORTCUTS };
  for (const { id } of KEYBOARD_SHORTCUT_ACTIONS) {
    if (!(id in value)) continue;
    const shortcut = value[id];
    next[id] = shortcut ? normalizeShortcut(shortcut) : null;
  }
  return next;
}

function readKeyboardShortcuts(): KeyboardShortcutMap {
  if (cachedKeyboardShortcuts) return cachedKeyboardShortcuts;

  try {
    const parsed = JSON.parse(
      localStorage.getItem(KEYBOARD_SHORTCUTS_STORAGE_KEY) ?? "null",
    ) as unknown;
    cachedKeyboardShortcuts = isShortcutMap(parsed)
      ? normalizeShortcutMap(parsed)
      : DEFAULT_KEYBOARD_SHORTCUTS;
    return cachedKeyboardShortcuts;
  } catch {
    cachedKeyboardShortcuts = DEFAULT_KEYBOARD_SHORTCUTS;
    return DEFAULT_KEYBOARD_SHORTCUTS;
  }
}

function writeKeyboardShortcuts(shortcuts: KeyboardShortcutMap): void {
  cachedKeyboardShortcuts = shortcuts;
  try {
    localStorage.setItem(KEYBOARD_SHORTCUTS_STORAGE_KEY, JSON.stringify(shortcuts));
  } catch {
    // Durable app settings still get the write below.
  }

  window.dispatchEvent(new Event(CHANGE_EVENT));
  void setAppSetting(KEYBOARD_SHORTCUTS_STORAGE_KEY, shortcuts);
}

function subscribe(callback: () => void) {
  const handleChange = () => {
    callback();
  };
  const handleStorage = () => {
    cachedKeyboardShortcuts = null;
    callback();
  };

  window.addEventListener(CHANGE_EVENT, handleChange);
  window.addEventListener("storage", handleStorage);

  return () => {
    window.removeEventListener(CHANGE_EVENT, handleChange);
    window.removeEventListener("storage", handleStorage);
  };
}

export async function hydrateKeyboardShortcuts() {
  const stored = await getAppSetting<unknown>(KEYBOARD_SHORTCUTS_STORAGE_KEY);
  const shortcuts = isShortcutMap(stored)
    ? normalizeShortcutMap(stored)
    : readKeyboardShortcuts();
  cachedKeyboardShortcuts = shortcuts;

  try {
    localStorage.setItem(KEYBOARD_SHORTCUTS_STORAGE_KEY, JSON.stringify(shortcuts));
  } catch {
    // The in-memory UI still receives the event below.
  }

  window.dispatchEvent(new Event(CHANGE_EVENT));
  if (!isShortcutMap(stored)) {
    void setAppSetting(KEYBOARD_SHORTCUTS_STORAGE_KEY, shortcuts);
  }
}

export function setKeyboardShortcut(
  action: KeyboardShortcutAction,
  shortcut: KeyboardShortcut | null,
) {
  const shortcuts = { ...readKeyboardShortcuts() };
  const normalizedShortcut = shortcut ? normalizeShortcut(shortcut) : null;

  if (normalizedShortcut) {
    for (const { id } of KEYBOARD_SHORTCUT_ACTIONS) {
      if (id !== action && areShortcutsEqual(shortcuts[id], normalizedShortcut)) {
        shortcuts[id] = null;
      }
    }
  }

  shortcuts[action] = normalizedShortcut;
  writeKeyboardShortcuts(shortcuts);
}

export function resetKeyboardShortcut(action: KeyboardShortcutAction) {
  setKeyboardShortcut(action, DEFAULT_KEYBOARD_SHORTCUTS[action]);
}

export function resetKeyboardShortcuts() {
  writeKeyboardShortcuts(normalizeShortcutMap(DEFAULT_KEYBOARD_SHORTCUTS));
}

export function useKeyboardShortcuts() {
  return useSyncExternalStore(
    subscribe,
    readKeyboardShortcuts,
    () => DEFAULT_KEYBOARD_SHORTCUTS,
  );
}

export function captureKeyboardShortcut(event: KeyboardEvent): KeyboardShortcut | null {
  if (modifierCodes.has(event.code)) return null;

  const shortcut: KeyboardShortcut = {
    code: event.code,
    key: event.key,
  };

  if (event.ctrlKey) shortcut.primary = true;
  if (event.altKey) shortcut.alt = true;
  if (event.shiftKey) shortcut.shift = true;
  if (event.metaKey) shortcut.meta = true;

  return normalizeShortcut(shortcut);
}

export function eventMatchesShortcut(
  event: KeyboardEvent,
  shortcut: KeyboardShortcut | null,
): boolean {
  if (!shortcut) return false;

  return (
    event.code === shortcut.code
    && event.ctrlKey === Boolean(shortcut.primary)
    && event.metaKey === Boolean(shortcut.meta)
    && event.altKey === Boolean(shortcut.alt)
    && event.shiftKey === Boolean(shortcut.shift)
  );
}

export function areShortcutsEqual(
  first: KeyboardShortcut | null,
  second: KeyboardShortcut | null,
): boolean {
  if (!first || !second) return first === second;
  return (
    first.code === second.code
    && Boolean(first.primary) === Boolean(second.primary)
    && Boolean(first.meta) === Boolean(second.meta)
    && Boolean(first.alt) === Boolean(second.alt)
    && Boolean(first.shift) === Boolean(second.shift)
  );
}

function getKeyLabel(shortcut: KeyboardShortcut): string {
  if (shortcut.code === "Space") return "Space";
  if (shortcut.code === "ArrowLeft") return "Left";
  if (shortcut.code === "ArrowRight") return "Right";
  if (shortcut.code === "ArrowUp") return "Up";
  if (shortcut.code === "ArrowDown") return "Down";
  if (shortcut.code === "Escape") return "Esc";
  if (shortcut.code === "Backspace") return "Backspace";
  if (shortcut.code === "Delete") return "Delete";
  if (shortcut.code === "Enter") return "Enter";
  if (/^Key[A-Z]$/.test(shortcut.code)) return shortcut.code.slice(3);
  if (/^Digit[0-9]$/.test(shortcut.code)) return shortcut.code.slice(5);
  return shortcut.key.length === 1 ? shortcut.key.toUpperCase() : shortcut.key;
}

export function formatKeyboardShortcut(shortcut: KeyboardShortcut | null): string {
  if (!shortcut) return "None";

  const parts: string[] = [];
  if (shortcut.primary) parts.push("Ctrl");
  if (shortcut.meta) parts.push("Meta");
  if (shortcut.alt) parts.push("Alt");
  if (shortcut.shift) parts.push("Shift");
  parts.push(getKeyLabel(shortcut));
  return parts.join(" + ");
}
