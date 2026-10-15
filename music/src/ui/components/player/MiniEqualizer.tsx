// Modified for TarisOS (Taris Music) by George Dobreff ("Witcher") and contributors, 2026.
import { useCallback, useId, useRef, useState } from "react";
import type { KeyboardEvent, PointerEvent } from "react";
import { cn } from "@/lib/utils";
import { Switch } from "@/components/motion/switch";
import {
  activeEqualizerPreset,
  EQUALIZER_BANDS_HZ,
  EQUALIZER_MAX_DB,
  EQUALIZER_PRESETS,
  isEqualizerFlat,
  setEqualizer,
  setEqualizerEnabled,
  useEqualizer,
  useEqualizerEnabled,
} from "../../settings/equalizer";

/** Height of the bar well. Ten of these plus the preamp fit a 256px popup without scrolling. */
const WELL_PX = 56;

const clamp = (value: number, lo: number, hi: number) => Math.min(hi, Math.max(lo, value));

/**
 * One vertical bar: a bipolar gain control, filling up from centre for a boost and down for a
 * cut. `RangeSlider` is horizontal only — built for a scale read left to right, not a bar read
 * by height — so this is its own small control rather than a forced reuse of a component whose
 * pointer maths run the wrong axis.
 */
function MiniEqBar({
  label,
  value,
  onChange,
}: {
  label: string;
  value: number;
  onChange: (value: number) => void;
}) {
  const trackRef = useRef<HTMLDivElement>(null);
  const [dragging, setDragging] = useState(false);

  const commitFromY = useCallback(
    (clientY: number) => {
      const rect = trackRef.current?.getBoundingClientRect();
      if (!rect) return;
      // Centre of the well is 0 dB; distance from it, signed, scales to the full range.
      const half = rect.height / 2;
      const fromCentre = rect.top + half - clientY;
      const gain = Math.round(clamp((fromCentre / half) * EQUALIZER_MAX_DB, -EQUALIZER_MAX_DB, EQUALIZER_MAX_DB));
      onChange(gain);
    },
    [onChange],
  );

  const onPointerDown = (event: PointerEvent<HTMLDivElement>) => {
    event.currentTarget.setPointerCapture(event.pointerId);
    setDragging(true);
    commitFromY(event.clientY);
  };

  const onPointerMove = (event: PointerEvent<HTMLDivElement>) => {
    if (!dragging) return;
    commitFromY(event.clientY);
  };

  const endDrag = (event: PointerEvent<HTMLDivElement>) => {
    event.currentTarget.releasePointerCapture?.(event.pointerId);
    setDragging(false);
  };

  const onKeyDown = (event: KeyboardEvent<HTMLDivElement>) => {
    const map: Record<string, number> = {
      ArrowUp: value + 1,
      ArrowDown: value - 1,
      Home: -EQUALIZER_MAX_DB,
      End: EQUALIZER_MAX_DB,
    };
    if (event.key in map) {
      event.preventDefault();
      onChange(clamp(map[event.key], -EQUALIZER_MAX_DB, EQUALIZER_MAX_DB));
    }
  };

  const ratio = value / EQUALIZER_MAX_DB;
  const fillPx = Math.abs(ratio) * (WELL_PX / 2);
  const fillTop = ratio >= 0 ? WELL_PX / 2 - fillPx : WELL_PX / 2;

  return (
    <div className="flex flex-col items-center gap-1">
      <div
        ref={trackRef}
        role="slider"
        tabIndex={0}
        aria-label={`${label} gain`}
        aria-orientation="vertical"
        aria-valuemin={-EQUALIZER_MAX_DB}
        aria-valuemax={EQUALIZER_MAX_DB}
        aria-valuenow={value}
        onPointerDown={onPointerDown}
        onPointerMove={onPointerMove}
        onPointerUp={endDrag}
        onPointerCancel={endDrag}
        onKeyDown={onKeyDown}
        style={{ height: WELL_PX }}
        className={cn(
          "relative w-3 touch-none select-none rounded-full bg-muted outline-none",
          "focus-visible:ring-2 focus-visible:ring-ring",
          "cursor-grab active:cursor-grabbing",
        )}
      >
        {/* Zero line — the reference every fill grows away from. */}
        <div className="pointer-events-none absolute inset-x-0 top-1/2 h-px -translate-y-1/2 bg-foreground/25" />
        <div
          className="absolute inset-x-0 rounded-full bg-foreground/40 transition-[top,height] duration-100"
          style={{ top: fillTop, height: fillPx }}
        />
        {/* The cap: what a finger or a screen reader's focus ring actually lands on. */}
        <div
          className="pointer-events-none absolute inset-x-0 h-1.5 rounded-full bg-foreground shadow-sm transition-[top] duration-100"
          style={{ top: clamp(WELL_PX / 2 - (ratio * (WELL_PX / 2)) - 3, -3, WELL_PX - 3) }}
        />
      </div>
      <span className="text-[9px] font-medium tabular-nums text-muted-foreground">{label}</span>
    </div>
  );
}

/**
 * The equaliser, shrunk to fit the speed/sleep-timer popup.
 *
 * Vertical bars rather than the settings page's horizontal ones — a popup this narrow has width
 * for a label or a slider but not both stacked ten times, and a bar you can read by height at a
 * glance is what an equaliser looks like everywhere outside this app's own settings page.
 */
export function MiniEqualizer() {
  const equalizer = useEqualizer();
  const enabled = useEqualizerEnabled();
  const flat = isEqualizerFlat(equalizer);
  const activePreset = activeEqualizerPreset(equalizer);
  const labelId = useId();

  const setBand = (index: number, gain: number) => {
    const bandsDb = equalizer.bandsDb.slice();
    bandsDb[index] = gain;
    setEqualizer({ ...equalizer, bandsDb });
  };

  return (
    <div className="flex flex-col gap-2.5 border-t border-border pt-3">
      <div className="flex items-center justify-between gap-2">
        <span id={labelId} className="text-xs font-medium text-foreground">
          Equaliser
        </span>
        <div className="flex items-center gap-2">
          <span className="text-[11px] text-muted-foreground">
            {enabled ? (flat ? "Flat" : "On") : "Off"}
          </span>
          <Switch
            checked={enabled}
            onCheckedChange={setEqualizerEnabled}
            aria-labelledby={labelId}
          />
        </div>
      </div>

      <div className={cn("flex flex-col gap-2", !enabled && "opacity-60")}>
        <div className="flex flex-wrap gap-1">
          {EQUALIZER_PRESETS.map((preset) => (
            <button
              key={preset.name}
              type="button"
              onClick={() => setEqualizer(preset.settings)}
              className={cn(
                "rounded-full px-2 py-0.5 text-[10px] font-medium transition-colors disabled:opacity-50",
                "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-ring",
                activePreset?.name === preset.name
                  ? "bg-primary text-primary-foreground"
                  : "bg-card text-foreground hover:bg-muted",
              )}
            >
              {preset.name}
            </button>
          ))}
        </div>

        <div className="flex items-end justify-between gap-1 px-0.5">
          {EQUALIZER_BANDS_HZ.map((hz, index) => (
            <MiniEqBar
              key={hz}
              label={hz >= 1000 ? `${hz / 1000}k` : String(hz)}
              value={equalizer.bandsDb[index]}
              onChange={(gain) => setBand(index, gain)}
            />
          ))}
        </div>
      </div>
    </div>
  );
}
