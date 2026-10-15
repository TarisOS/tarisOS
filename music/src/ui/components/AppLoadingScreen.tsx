// Modified for TarisOS (Taris Music) by George Dobreff ("Witcher") and contributors, 2026.
import { cn } from "@/lib/utils";

/*
 * The accent bloom, as a gradient rather than a blurred circle.
 *
 * It was a 420px solid disc with `blur-[120px]`. A filter that large is not cheap the way a
 * background is: the element becomes its own compositor layer, and Chromium has to allocate an
 * intermediate texture expanded by roughly three times the radius on every side — a 420px disc
 * rasterising into something past 1100px square, in multiple passes, on the startup screen
 * where the GPU process is still warming up.
 *
 * A blurred solid circle is a radial gradient. This one is drawn straight into the raster pass:
 * no filter, no layer, no intermediate. The box is grown to 660px because the gradient has to
 * cover the area the blur used to bleed into.
 */
const LOADING_GLOW =
  "radial-gradient(circle, color-mix(in oklab, var(--color-primary) 7%, transparent) 0%, transparent 70%)";

const LOADING_LINES = [
  " Finding your rhythm...",
  " Loading your library...",
  " Tuning the soundstage...",
  " Warming up the strings...",
  " Counting in...",
  " Preparing your session...",
  " Syncing your music...",
  " Building today's vibe...",
];

interface AppLoadingScreenProps {
  isLeaving: boolean;
}

export function AppLoadingScreen({ isLeaving }: AppLoadingScreenProps) {
  const loadingLine = LOADING_LINES[Math.floor(Math.random() * LOADING_LINES.length)];

  return (
    <div
      className={cn(
        "fixed inset-0 z-[100] grid place-items-center rounded-3xl bg-background transition-opacity duration-200",
        isLeaving ? "pointer-events-none opacity-0" : "opacity-100",
      )}
      role="status"
      aria-label="Loading"
      aria-live="polite"
    >
      {/* Accent bloom behind the loading line */}
      <div
        className="pointer-events-none absolute left-1/2 top-1/2 size-[660px] -translate-x-1/2 -translate-y-1/2 rounded-full"
        style={{ background: LOADING_GLOW }}
      />

      <strong className="relative text-sm font-medium text-foreground">{loadingLine}</strong>
    </div>
  );
}
