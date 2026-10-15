// Modified for TarisOS (Taris Music) by George Dobreff ("Witcher") and contributors, 2026.
import { useState } from "react";
import { cn } from "@/lib/utils";
import { Tooltip } from "@/components/motion/tooltip";
import { DiscordIcon, LastFmIcon, LoginIcon, SettingsIcon, YouTubeMusicIcon } from "@/ui/icons";
import { DiscordRpcService } from "../../player/DiscordRPC";
import { useDiscordPresenceEnabled } from "../settings/discord";
import { setLastFmScrobblingEnabled, useLastFmScrobblingEnabled } from "../settings/lastfm";
import { setYouTubeScrobbling, useYouTubeScrobbling } from "../settings/youtubeAccount";
import { Button } from "@/components/motion/button";
import { libraryController, useLibraryState } from "../../player/playerStore";
import { AccountAvatar, AccountSwitcher, GoogleAccountSwitcher } from "./AccountSwitcher";
import { GoogleSignInButton } from "./GoogleSignInButton";
import { DownloadsPanel } from "./DownloadsPanel";
import { FloatingPanel } from "./FloatingPanel";
import { NotificationsPanel } from "./NotificationsPanel";
import { useToolbarItemVisible } from "../settings/toolbarItems";

interface TitleBarProps {
  sidebarWidth: number;
  isHomeActive: boolean;
  onNavigateHome: () => void;
  onOpenSettings: () => void;
  onOpenDownloads?: () => void;
}

const ACCOUNT_PANEL_ITEM =
  "flex w-full items-center gap-2.5 rounded-lg px-2 py-2 text-left text-sm text-foreground transition-colors hover:bg-card focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-ring";

export function TitleBar({
  sidebarWidth,
  isHomeActive,
  onNavigateHome,
  onOpenSettings,
  onOpenDownloads,
}: TitleBarProps) {
  const libraryState = useLibraryState();
  const account = libraryState.library?.account;
  // Confirmed by YouTube, not merely by having a library on screen — a cache with no expiry
  // will happily supply one long after the session behind it stopped working.
  const isSignedIn = libraryState.status === "ready"
    && Boolean(account)
    && libraryState.sessionConfirmedAt !== null;
  // Startup restores the session before it can say whether there is one — "Not signed in" is
  // the wrong answer while that is still happening.
  const isConnecting = !isSignedIn
    && (libraryState.status === "restoring"
      || libraryState.status === "loading"
      || libraryState.status === "authorizing");
  const [isAccountPanelOpen, setIsAccountPanelOpen] = useState(false);
  const discordEnabled = useDiscordPresenceEnabled();
  const lastFmEnabled = useLastFmScrobblingEnabled();
  const ytScrobblingEnabled = useYouTubeScrobbling();
  const notificationsVisible = useToolbarItemVisible("notifications");
  const downloadsVisible = useToolbarItemVisible("downloads");
  const discordVisible = useToolbarItemVisible("discord");
  const lastFmVisible = useToolbarItemVisible("lastfm");
  const ytMusicVisible = useToolbarItemVisible("ytmusic");
  const hideHomeText = sidebarWidth <= 120;

  return (
    <div className="relative z-30 flex h-[var(--titlebar-height)] shrink-0 items-stretch bg-background">
      <button
        type="button"
        style={{ width: `${sidebarWidth}px` }}
        className={cn(
          "flex shrink-0 items-center gap-1 px-4 text-sm font-bold  transition-colors focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring focus-visible:ring-inset",
          isHomeActive ? "text-primary" : "text-muted-foreground hover:text-foreground",
          hideHomeText && "justify-center gap-0 px-0",
        )}
        onClick={onNavigateHome}
        aria-label="Home"
        aria-current={isHomeActive ? "page" : undefined}
      >
        {!hideHomeText && <h3>Music</h3>}
      </button>

      <div className="min-w-6 flex-1" />

      {/* App actions, at the right end of the title bar */}
      <div className="flex shrink-0 items-center gap-1 pl-2 pr-1" aria-label="App actions">
        {/*
          Integration toggles.

          Both share what the user is listening to with a third party, which is exactly the kind
          of thing worth being able to stop in one click rather than three — hence a toolbar
          toggle rather than only a setting buried in a panel. Dimmed when off so the current
          state reads at a glance without a label.
        */}
        {notificationsVisible && (
          <NotificationsPanel signedIn={libraryState.status === "ready"} />
        )}
        {downloadsVisible && <DownloadsPanel onOpenDownloads={onOpenDownloads} />}
        {discordVisible && (
        <Tooltip
          side="bottom"
          content={discordEnabled ? "Discord presence on" : "Discord presence off"}
        >
          <Button
            variant="ghost"
            size="icon"
            onClick={() => void DiscordRpcService.setEnabled(!discordEnabled)}
            aria-pressed={discordEnabled}
            aria-label={
              discordEnabled ? "Turn off Discord presence" : "Turn on Discord presence"
            }
          >
            <DiscordIcon
              size={16}
              aria-hidden="true"
              className={cn(
                "transition-opacity",
                discordEnabled ? "opacity-100 text-primary" : "opacity-40",
              )}
            />
          </Button>
        </Tooltip>
        )}
        {lastFmVisible && (
        <Tooltip
          side="bottom"
          content={lastFmEnabled ? "Last.fm scrobbling on" : "Last.fm scrobbling off"}
        >
          <Button
            variant="ghost"
            size="icon"
            onClick={() => setLastFmScrobblingEnabled(!lastFmEnabled)}
            aria-pressed={lastFmEnabled}
            aria-label={
              lastFmEnabled ? "Turn off Last.fm scrobbling" : "Turn on Last.fm scrobbling"
            }
          >
            <LastFmIcon
              size={16}
              aria-hidden="true"
              className={cn(
                "transition-opacity",
                lastFmEnabled ? "opacity-100 text-primary" : "opacity-40",
              )}
            />
          </Button>
        </Tooltip>
        )}
        {ytMusicVisible && (
        <Tooltip
          side="bottom"
          content={
            ytScrobblingEnabled
              ? "Adding plays to YouTube Music history"
              : "Not adding plays to YouTube Music history"
          }
        >
          <Button
            variant="ghost"
            size="icon"
            onClick={() => setYouTubeScrobbling(!ytScrobblingEnabled)}
            aria-pressed={ytScrobblingEnabled}
            aria-label={
              ytScrobblingEnabled
                ? "Stop adding plays to YouTube Music history"
                : "Add plays to YouTube Music history"
            }
          >
            <YouTubeMusicIcon
              size={16}
              aria-hidden="true"
              className={cn(
                "transition-opacity",
                ytScrobblingEnabled ? "opacity-100 text-primary" : "opacity-40",
              )}
            />
          </Button>
        </Tooltip>
        )}

        <Tooltip side="bottom" content="Settings">
        <Button
            variant='ghost'
          size='icon'
            
            onClick={onOpenSettings}
            aria-label="Open settings"
          >
            <SettingsIcon size={17} aria-hidden="true" />
          </Button>
        </Tooltip>

        {/* Only once signed in: an avatar that opens nothing is worse than no avatar. The
            panel is portalled because the title bar clips its children. */}
        {/* Always present, signed in or not: when signed out it is the way *in*, so hiding
            it would leave the toolbar with no account affordance at all. */}
        <FloatingPanel
          open={isAccountPanelOpen}
          onOpenChange={setIsAccountPanelOpen}
          side="bottom"
          className="w-64"
          trigger={
            <Tooltip side="bottom" content={isSignedIn ? account?.name || "Account" : "Sign in"}>
              <button
                type="button"
                onClick={() => setIsAccountPanelOpen((open) => !open)}
                aria-haspopup="menu"
                aria-expanded={isAccountPanelOpen}
                aria-label={isSignedIn ? `Account: ${account?.name || "YouTube Music"}` : "Sign in"}
                className={cn(
                  "ml-0.5 grid size-7 place-items-center rounded-full transition-shadow",
                  "focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring",
                  isAccountPanelOpen && "ring-1 ring-border",
                )}
              >
                <AccountAvatar
                  artworkUrl={isSignedIn ? account?.artworkUrl : undefined}
                  className="size-7"
                  iconSize={15}
                />
              </button>
            </Tooltip>
          }
        >
          {isSignedIn ? (
            <div className="flex flex-col gap-1">
              {/* Who you are, before what you can do about it: the avatar in the toolbar is
                  ambiguous on its own, and this line is the answer to the click. */}
              <div className="flex items-center gap-2.5 px-1 py-1.5">
                <AccountAvatar artworkUrl={account?.artworkUrl} className="size-9" iconSize={18} />
                <span className="flex min-w-0 flex-col">
                  <span className="truncate text-sm font-medium text-foreground">
                    {account?.name || "YouTube Music"}
                  </span>
                  <span className="truncate text-xs text-muted-foreground">Signed in</span>
                </span>
              </div>

              <span className="my-0.5 h-px bg-border" aria-hidden="true" />

              {/* Separate Google logins first, channels within the active one after — labeled
                  so the two are never mistaken for one undifferentiated list. This is a quick
                  switcher, not where accounts are added or removed, so a section (label
                  included) renders nothing at all when there is only one option in it. */}
              <GoogleAccountSwitcher
                libraryController={libraryController}
                onSwitched={() => setIsAccountPanelOpen(false)}
                label="Account"
              />

              <AccountSwitcher
                libraryController={libraryController}
                onSwitched={() => setIsAccountPanelOpen(false)}
                label="Channel"
              />

              <button
                type="button"
                className={ACCOUNT_PANEL_ITEM}
                onClick={() => {
                  setIsAccountPanelOpen(false);
                  onOpenSettings();
                }}
              >
                <SettingsIcon size={16} aria-hidden="true" />
                Account settings
              </button>
            </div>
          ) : (
            /*
             * Signed out, this panel is the way in, so it says what signing in gets you rather
             * than only offering a verb. The button hands off to settings because that screen
             * is where the device-code prompt is rendered — starting the flow from here would
             * put the code somewhere nobody is looking.
             */
            <div className="flex flex-col items-center gap-1 px-2 pb-2 pt-3 text-center">
              <span className="grid size-11 place-items-center rounded-full bg-primary/10 text-primary">
                <LoginIcon size={20} aria-hidden="true" />
              </span>
              <p className="mt-1 text-sm font-semibold text-foreground">
                {isConnecting ? "Connecting…" : "Not signed in"}
              </p>
              <p className="text-xs leading-relaxed text-muted-foreground">
                {isConnecting
                  ? "Restoring your YouTube Music session."
                  : "Connect YouTube Music for your library, playlists and likes."}
              </p>
              <GoogleSignInButton
                className="mt-2"
                fullWidth
                isBusy={isConnecting}
                onClick={() => {
                  setIsAccountPanelOpen(false);
                  onOpenSettings();
                }}
              />
            </div>
          )}
        </FloatingPanel>
      </div>

    </div>
  );
}
