// Modified for TarisOS (Taris Music) by George Dobreff ("Witcher") and contributors, 2026.
// Learn more about Tauri commands at https://tauri.app/develop/calling-rust/
use base64::{engine::general_purpose::STANDARD, Engine as _};
#[cfg(not(debug_assertions))]
use portpicker::pick_unused_port;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::fmt;
use std::fs::{self, File, OpenOptions};
use std::io::Write;
use std::net::{IpAddr, Ipv4Addr, Ipv6Addr};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};
use std::sync::{Arc, Mutex, OnceLock};
use std::thread;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

macro_rules! eprintln {
    ($($arg:tt)*) => {{
        let message = $crate::sanitize_log_message(&format!($($arg)*));
        std::eprintln!("{}", message);
        $crate::append_log_line(format_args!("{}", message));
    }};
}

#[cfg(not(debug_assertions))]
use tauri::utils::config::FrontendDist;
#[cfg(not(debug_assertions))]
use tauri::utils::config_v1::WindowUrl;

use tauri::{Emitter, Manager};

// Account slot ids (generate_slot_id)
use rand::{rngs::OsRng, RngCore};

mod linux_media;

mod audio;
mod discord_rpc;
mod equalizer;
mod opus_source;
mod lastfm;

// Keep the legacy service name so existing sign-in credentials survive the product rename.
const KEYRING_SERVICE: &str = "com.ytmusicdock.app";

/// Durable settings store.
const APP_SETTINGS_FILE_NAME: &str = "settings-v1.json";

const KEYRING_USER: &str = "youtube-oauth";
const YOUTUBE_COOKIE_KEYRING_USER: &str = "youtube-music-cookie";
/// Slot id for the one account that existed before multi-account support.
///
/// Pinned rather than randomly generated so migrating an existing install keeps using the
/// *exact* original shared webview partition (`YOUTUBE_LOGIN_DATA_DIR` /
/// `YOUTUBE_LOGIN_DATA_STORE_ID`, unsuffixed) instead of a fresh, empty one — see
/// `login_partition_directory_name`. A fresh partition has no warm Google browser session in
/// it, which would have made silent refresh less reliable for every existing user on the very
/// next launch after this shipped.
const LEGACY_ACCOUNT_SLOT_ID: &str = "legacy-primary-account";
const YOUTUBE_LOGIN_WINDOW: &str = "youtube-music-login";
const YOUTUBE_LOGIN_URL: &str = "https://accounts.google.com/ServiceLogin?service=youtube&continue=https%3A%2F%2Fmusic.youtube.com%2F";
/// Storage partition for the sign-in webview, so clearing it cannot touch the app's own.
///
/// `clear_all_browsing_data` is a *profile*-wide operation, and every webview in the process
/// shares one profile by default. The login window used to clear
/// that shared profile twice per sign-in cycle, which wiped the main window's localStorage:
/// the downloads manifest, local playlists, play history, tabs, shortcuts, the lot. Worse, a
/// lost manifest made the next launch delete every downloaded file as an orphan.
const YOUTUBE_LOGIN_DATA_DIR: &str = "youtube-login-webview";
const YOUTUBE_COOKIE_CHUNK_SIZE: usize = 900;
/// Bytes: `YOUTUBE_COOKIE_CHUNK_SIZE * YOUTUBE_COOKIE_MAX_CHUNKS` ~= 57.6 KB. Saves write one
/// entry now; the chunks are what older saves left, read and removed by count.
///
/// One account's cookie header used to be the whole stored blob; it is now one entry in a JSON
/// array of them, so the ceiling went up from a single session (~14.4 KB of headroom) to
/// comfortably cover several. Nobody is juggling dozens of Google accounts in a desktop music
/// app — this is generous, not unlimited.
const YOUTUBE_COOKIE_MAX_CHUNKS: usize = 64;
/// How often a rotation of `YOUTUBE_SLOW_PERSIST_COOKIES` is written back to secure storage.
///
/// Not on every response: Google rotates SIDCC on almost all of them, and a save rewrites the
/// whole keyring entry. Every *other* rotation is written at once —
/// see `YOUTUBE_SLOW_PERSIST_COOKIES` for why that distinction is the whole game.
const YOUTUBE_COOKIE_PERSIST_INTERVAL: Duration = Duration::from_secs(300);
/// Cookies whose rotation may be persisted late, because nothing authenticates with them.
///
/// Everything else — `__Secure-*PSIDTS` above all — is written the moment it changes. Google
/// retires the superseded value, so quitting inside the throttle window left a dead credential
/// on disk and the next launch presented it: the session looked lost overnight when it was only
/// lost between the last rotation and the last write.
const YOUTUBE_SLOW_PERSIST_COOKIES: [&str; 3] = ["SIDCC", "__Secure-1PSIDCC", "__Secure-3PSIDCC"];
/// Seconds a silent renewal may spend before giving up and asking the user.
///
/// Generous enough for a cold webview start plus the Google redirect chain, because the cost of
/// being a second too impatient is a sign-in prompt the user did not need.
const YOUTUBE_SILENT_REFRESH_POLLS: u32 = 25;
const DEFAULT_CACHE_MAX_BYTES: u64 = 4 * 1024 * 1024 * 1024;
const CURRENT_LOG_FILE_NAME: &str = "current.log";

static APP_LOG_FILE: OnceLock<Mutex<Option<File>>> = OnceLock::new();

struct CacheLock(Mutex<()>);
struct AppSettingsLock(Mutex<()>);
/// Serializes every read-modify-write of the YouTube account store — sign-in, silent refresh,
/// switch, remove, and the ambient cookie-rotation persist inside `proxy_http_request` all go
/// through it. Without this, two of those racing (e.g. a rotation persisting at the same moment
/// a different window removes an account) could interleave: both read the same base, and
/// whichever writes last silently undoes the other's change — an account switch reverting, or a
/// removed account coming back.
struct AccountStoreLock(Mutex<()>);

/// The live YouTube cookie, kept current from every response that rotates it.
///
/// The signed-in session used to be a snapshot taken once at sign-in and replayed forever,
/// with every `Set-Cookie` thrown away. Google rotates `SIDCC` and `__Secure-*PSIDTS`
/// continuously and stops trusting a session that keeps presenting stale ones, so the app
/// quietly lost its authentication overnight while still looking signed in. This is the one
/// authoritative copy: `proxy_http_request` stamps outgoing requests from it and folds every
/// `Set-Cookie` back into it.
#[derive(Default)]
struct CookieJarState {
    cookie: Option<String>,
    persisted_at: Option<Instant>,
}

struct YoutubeCookieJar(Mutex<CookieJarState>);

fn parse_cookie_header(header: &str) -> Vec<(String, String)> {
    header
        .split(';')
        .filter_map(|part| part.trim().split_once('='))
        .map(|(name, value)| (name.trim().to_string(), value.trim().to_string()))
        .collect()
}

fn serialize_cookie_pairs(pairs: &[(String, String)]) -> String {
    pairs
        .iter()
        .map(|(name, value)| format!("{name}={value}"))
        .collect::<Vec<_>>()
        .join("; ")
}

/// The leading `name=value` of a `Set-Cookie` value.
///
/// The attributes after it describe where a browser should send the cookie, and this jar has
/// exactly one destination.
fn split_set_cookie(set_cookie: &str) -> Option<(&str, &str)> {
    let (name, value) = set_cookie.split(';').next()?.split_once('=')?;
    let name = name.trim();
    if name.is_empty() {
        return None;
    }
    Some((name, value.trim()))
}

/// Folds one `Set-Cookie` value into the jar, reporting whether anything changed.
fn apply_set_cookie(pairs: &mut Vec<(String, String)>, set_cookie: &str) -> bool {
    let Some((name, value)) = split_set_cookie(set_cookie) else {
        return false;
    };
    let name = name.to_string();
    let value = value.to_string();

    // Google clears a cookie by echoing it back empty or as a tombstone rather than by
    // omitting it. Keeping those would keep presenting a value the server has retired.
    if value.is_empty() || value == "EXPIRED" || value == "deleted" {
        let before = pairs.len();
        pairs.retain(|(existing, _)| existing != &name);
        return pairs.len() != before;
    }

    match pairs.iter_mut().find(|(existing, _)| existing == &name) {
        Some(entry) if entry.1 == value => false,
        Some(entry) => {
            entry.1 = value;
            true
        }
        None => {
            pairs.push((name, value));
            true
        }
    }
}

/// Joins an error with its full `.source()` chain, so a wrapper like reqwest's "error sending
/// request for url" comes with the DNS/TLS/connection failure underneath it instead of hiding it.
fn error_cause_chain(error: &dyn std::error::Error) -> String {
    let mut parts = vec![error.to_string()];
    let mut source = error.source();
    while let Some(cause) = source {
        parts.push(cause.to_string());
        source = cause.source();
    }
    parts.join(" -> caused by: ")
}

fn is_youtube_cookie_host(url: &url::Url) -> bool {
    url.host_str()
        .is_some_and(|host| host == "youtube.com" || host.ends_with(".youtube.com"))
}

/// Whether this rotation may wait for `YOUTUBE_COOKIE_PERSIST_INTERVAL` before being stored.
fn is_slow_persist_cookie(set_cookie: &str) -> bool {
    split_set_cookie(set_cookie)
        .is_some_and(|(name, _)| YOUTUBE_SLOW_PERSIST_COOKIES.contains(&name))
}

/// Which Google account a cookie header belongs to, as far as the app needs to care.
///
/// Used for one question: did signing in again land on the same account? A re-mint of a lapsed
/// session keeps this value, so answering "same" is what lets a renewal keep the cached library
/// and the chosen channel instead of resyncing from scratch. It is a fingerprint, never logged
/// and never handed to the frontend — only the boolean answer is.
fn cookie_account_identity(cookie: &str) -> Option<String> {
    let pairs = parse_cookie_header(cookie);
    ["SAPISID", "__Secure-3PAPISID", "__Secure-1PAPISID"]
        .iter()
        .find_map(|name| {
            pairs
                .iter()
                .find(|(existing, value)| existing == name && !value.is_empty())
                .map(|(_, value)| value.clone())
        })
}

fn generate_slot_id() -> String {
    let mut bytes = [0_u8; 16];
    OsRng.fill_bytes(&mut bytes);
    bytes.iter().map(|byte| format!("{byte:02x}")).collect()
}

fn unix_millis() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|duration| duration.as_millis() as u64)
        .unwrap_or(0)
}

/// One signed-in Google account's durable session.
///
/// `identity` is the same fingerprint `cookie_account_identity` documents: never serialized to
/// the frontend (see the `YoutubeAccountSummary` DTO, which omits it entirely), kept only so a
/// re-authentication of an already-stored account can be recognized as a refresh rather than a
/// new slot.
#[derive(Serialize, Deserialize, Clone, Default)]
#[serde(rename_all = "camelCase")]
struct StoredYoutubeAccount {
    slot_id: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    identity: Option<String>,
    cookie: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    display_name: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    avatar_url: Option<String>,
    added_at_ms: u64,
}

/// Every Google account with a stored session, and which one is active.
///
/// This is the one blob persisted through the existing `save_youtube_music_cookie` /
/// `load_youtube_music_cookie_entries` transport — the keyring entry — unchanged
/// underneath. Only what gets stored changed, from a bare cookie header to this struct's JSON.
#[derive(Serialize, Deserialize, Clone, Default)]
#[serde(rename_all = "camelCase")]
struct YoutubeAccountStore {
    #[serde(skip_serializing_if = "Option::is_none")]
    active_slot_id: Option<String>,
    accounts: Vec<StoredYoutubeAccount>,
}

impl YoutubeAccountStore {
    /// A bare cookie header from before multi-account support, as the one stored account.
    fn from_legacy_cookie(cookie: &str, slot_id: String) -> Self {
        YoutubeAccountStore {
            active_slot_id: Some(slot_id.clone()),
            accounts: vec![StoredYoutubeAccount {
                slot_id,
                identity: cookie_account_identity(cookie),
                cookie: cookie.to_string(),
                display_name: None,
                avatar_url: None,
                added_at_ms: unix_millis(),
            }],
        }
    }

    /// The active account, self-healing to the first stored one if the recorded active slot id
    /// does not (or no longer) match anything — corrupt state should degrade to "signed in as
    /// *someone*" rather than "signed out" when there is clearly at least one stored session.
    fn active(&self) -> Option<&StoredYoutubeAccount> {
        self.active_slot_id
            .as_deref()
            .and_then(|id| self.find(id))
            .or_else(|| self.accounts.first())
    }

    fn find(&self, slot_id: &str) -> Option<&StoredYoutubeAccount> {
        self.accounts.iter().find(|account| account.slot_id == slot_id)
    }

    fn find_by_identity(&self, identity: &str) -> Option<&StoredYoutubeAccount> {
        self.accounts.iter().find(|account| account.identity.as_deref() == Some(identity))
    }

    /// Interactive sign-in landed on `cookie`. Refreshes the matching stored account in place
    /// when this identity is already known — so re-authenticating an account you already have
    /// never creates a duplicate slot — otherwise stores it fresh under `candidate_slot_id`.
    /// Either way the result is active afterward.
    ///
    /// Returns the slot id that ended up holding this cookie (the caller's candidate, or the
    /// existing one it matched) and whether that differs from whatever was active before —
    /// the signal for whether this is a new account instead of a lapsed-session renewal.
    fn upsert_signed_in_account(&mut self, cookie: &str, candidate_slot_id: String) -> (String, bool) {
        let previously_active = self.active_slot_id.clone();
        let identity = cookie_account_identity(cookie);
        let matched_slot_id = identity
            .as_deref()
            .and_then(|identity| self.find_by_identity(identity))
            .map(|account| account.slot_id.clone());

        let slot_id = match matched_slot_id {
            Some(existing_slot_id) => {
                if let Some(account) =
                    self.accounts.iter_mut().find(|account| account.slot_id == existing_slot_id)
                {
                    account.cookie = cookie.to_string();
                }
                existing_slot_id
            }
            None => {
                self.accounts.push(StoredYoutubeAccount {
                    slot_id: candidate_slot_id.clone(),
                    identity,
                    cookie: cookie.to_string(),
                    display_name: None,
                    avatar_url: None,
                    added_at_ms: unix_millis(),
                });
                candidate_slot_id
            }
        };
        self.active_slot_id = Some(slot_id.clone());
        let account_changed = previously_active.as_deref() != Some(slot_id.as_str());
        (slot_id, account_changed)
    }

    /// Removes one stored account. When it was the active one, another stored account (if any)
    /// becomes active in its place — the whole point being that losing one account should not
    /// force the others out too. Returns the newly active cookie, if any, and whether a slot
    /// actually existed to remove.
    fn remove(&mut self, slot_id: &str) -> (Option<String>, bool) {
        let existed = self.accounts.iter().any(|account| account.slot_id == slot_id);
        self.accounts.retain(|account| account.slot_id != slot_id);
        if self.active_slot_id.as_deref() == Some(slot_id) {
            self.active_slot_id = self.accounts.first().map(|account| account.slot_id.clone());
        }
        (self.active().map(|account| account.cookie.clone()), existed)
    }

    /// Makes a stored account active, e.g. for a switch that does not need the browser at all.
    /// `None` means it is not (or no longer) stored — removed from another window, perhaps.
    fn switch_active(&mut self, slot_id: &str) -> Option<String> {
        let cookie = self.find(slot_id)?.cookie.clone();
        self.active_slot_id = Some(slot_id.to_string());
        Some(cookie)
    }
}

/// Merges rotated cookies into the jar, returning the new header when it changed.
fn refresh_youtube_cookie_jar(
    app: &tauri::AppHandle,
    jar: &YoutubeCookieJar,
    account_lock: &AccountStoreLock,
    set_cookies: &[String],
) -> Option<String> {
    let (merged, should_persist) = {
        let mut state = jar.0.lock().ok()?;
        // No stored session means an anonymous request; it has no jar to update.
        let mut pairs = parse_cookie_header(state.cookie.as_deref()?);
        // Every cookie is applied; `any` would stop at the first change and drop the rest.
        let mut changed = false;
        let mut credential_changed = false;
        for set_cookie in set_cookies {
            if apply_set_cookie(&mut pairs, set_cookie) {
                changed = true;
                credential_changed |= !is_slow_persist_cookie(set_cookie);
            }
        }
        if !changed {
            return None;
        }

        let merged = serialize_cookie_pairs(&pairs);
        state.cookie = Some(merged.clone());
        // A rotated credential is written now; only the noisy ones wait for the interval.
        let should_persist = credential_changed
            || state
                .persisted_at
                .is_none_or(|at| at.elapsed() >= YOUTUBE_COOKIE_PERSIST_INTERVAL);
        if should_persist {
            state.persisted_at = Some(Instant::now());
        }
        (merged, should_persist)
    };

    // Outside the guard: the keyring write is slow and every other request wants the jar. The
    // jar itself is already updated above; this only needs to reach the durable store, so it
    // goes through the plain (non-jar-touching) persist rather than `persist_active_account_cookie`.
    if should_persist {
        let active_slot_id = match load_account_store(app) {
            Ok(store) => store.active_slot_id,
            Err(error) => {
                eprintln!(
                    "[internal][tauri][warn] youtube cookie persist skipped, account store unreadable: {}",
                    error.message
                );
                None
            }
        };
        match active_slot_id {
            Some(slot_id) => match persist_account_cookie(app, account_lock, &slot_id, &merged) {
                Ok(()) => eprintln!(
                    "[internal][tauri][info] youtube cookie rotated and persisted bytes={}",
                    merged.len()
                ),
                Err(error) => eprintln!(
                    "[internal][tauri][warn] youtube cookie persist failed: {}",
                    error.message
                ),
            },
            // No active slot to persist against (e.g. mid-removal on another window); the live
            // jar above still serves the rest of this session correctly.
            None => {}
        }
    }
    Some(merged)
}

#[derive(Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
struct CacheSettings {
    max_bytes: u64,
}

#[derive(Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
struct CacheEntry {
    key: String,
    value: String,
    updated_at_ms: u64,
    last_accessed_ms: u64,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct CacheStats {
    max_bytes: u64,
    used_bytes: u64,
    entry_count: usize,
}

#[derive(Serialize)]
struct CacheWriteResult {
    changed: bool,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct LocalAudioFile {
    path: String,
    title: String,
    artist: Option<String>,
    album: Option<String>,
    duration_sec: Option<u64>,
    /// Whether the file carries embedded cover art, so the UI knows to ask for it.
    has_artwork: bool,
}

/// Embedded cover art. Base64 because a `Vec<u8>` crosses Tauri's IPC as a JSON number array.
#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct LocalArtwork {
    mime_type: String,
    data_base64: String,
}

fn cache_error(message: impl Into<String>) -> CommandError {
    CommandError {
        message: message.into(),
    }
}

fn signed_googlevideo_local_address(url: &url::Url) -> Option<IpAddr> {
    if !url
        .host_str()
        .is_some_and(|host| host.ends_with(".googlevideo.com"))
    {
        return None;
    }

    let signed_ip = url.query_pairs().find_map(|(key, value)| {
        (key == "ip")
            .then(|| value.parse::<IpAddr>().ok())
            .flatten()
    })?;

    Some(match signed_ip {
        IpAddr::V4(_) => IpAddr::V4(Ipv4Addr::UNSPECIFIED),
        IpAddr::V6(_) => IpAddr::V6(Ipv6Addr::UNSPECIFIED),
    })
}

fn local_audio_mime_type(path: &Path) -> &'static str {
    match path
        .extension()
        .and_then(|extension| extension.to_str())
        .unwrap_or_default()
        .to_ascii_lowercase()
        .as_str()
    {
        "mp3" => "audio/mpeg",
        "m4a" | "mp4" => "audio/mp4",
        "aac" => "audio/aac",
        "flac" => "audio/flac",
        "wav" => "audio/wav",
        "ogg" | "oga" => "audio/ogg",
        "opus" => "audio/opus",
        "webm" => "audio/webm",
        _ => "application/octet-stream",
    }
}

fn is_local_audio_file(path: &Path) -> bool {
    matches!(
        path.extension()
            .and_then(|extension| extension.to_str())
            .unwrap_or_default()
            .to_ascii_lowercase()
            .as_str(),
        "mp3" | "m4a" | "mp4" | "aac" | "flac" | "wav" | "ogg" | "oga" | "opus" | "webm"
    )
}

fn local_audio_title(path: &Path) -> String {
    path.file_stem()
        .and_then(|name| name.to_str())
        .filter(|name| !name.trim().is_empty())
        .unwrap_or("Untitled")
        .to_string()
}

/**
 * One scanned file, described by its tags.
 *
 * The filename and the parent folder are the fallback, not the answer. The scan used to stop
 * there — every local track came back titled after its file, attributed to nothing, with no
 * duration and no art, because the tag reader existed only behind the tag editor.
 *
 * A tag read per file makes the scan slower than a `read_dir`; that is the cost of the metadata
 * being right, and it is paid once per page load rather than per play.
 */
fn local_audio_entry(path: &Path) -> LocalAudioFile {
    use lofty::file::{AudioFile, TaggedFileExt};
    use lofty::tag::Accessor;

    let mut entry = LocalAudioFile {
        path: path.to_string_lossy().to_string(),
        title: local_audio_title(path),
        artist: None,
        album: path
            .parent()
            .and_then(|parent| parent.file_name())
            .and_then(|name| name.to_str())
            .map(|name| name.to_string()),
        duration_sec: None,
        has_artwork: false,
    };

    // An unreadable or untagged file keeps the filesystem fallback rather than disappearing.
    let Ok(tagged) = lofty::read_from_path(path) else {
        return entry;
    };

    let duration = tagged.properties().duration().as_secs();
    if duration > 0 {
        entry.duration_sec = Some(duration);
    }

    let Some(tag) = tagged.primary_tag().or_else(|| tagged.first_tag()) else {
        return entry;
    };

    let text = |value: Option<std::borrow::Cow<'_, str>>| {
        value
            .map(|value| value.trim().to_string())
            .filter(|value| !value.is_empty())
    };

    if let Some(title) = text(tag.title()) {
        entry.title = title;
    }
    entry.artist = text(tag.artist());
    if let Some(album) = text(tag.album()) {
        entry.album = Some(album);
    }
    entry.has_artwork = !tag.pictures().is_empty();

    entry
}

/**
 * Reads an image the user picked, for the tag editor to preview and then embed.
 *
 * The magic-byte check is the point: a file picker filter is a suggestion, and lofty will
 * happily embed whatever bytes it is handed under whatever mime type it is told — which
 * produces a file every other player renders as a broken cover.
 */
#[tauri::command]
fn read_image_file(path: String) -> Result<LocalArtwork, CommandError> {
    use base64::Engine;

    let path = PathBuf::from(path);
    let data = fs::read(&path).map_err(|error| cache_error(format!("image read failed: {error}")))?;
    if data.len() > MAX_ARTWORK_BYTES {
        return Err(cache_error("that image is too large to embed"));
    }

    let mime_type = match data.as_slice() {
        [0xff, 0xd8, 0xff, ..] => "image/jpeg",
        [0x89, b'P', b'N', b'G', ..] => "image/png",
        [b'G', b'I', b'F', b'8', ..] => "image/gif",
        [b'B', b'M', ..] => "image/bmp",
        [b'R', b'I', b'F', b'F', _, _, _, _, b'W', b'E', b'B', b'P', ..] => "image/webp",
        _ => return Err(cache_error("that file is not a PNG, JPEG, GIF, BMP or WebP image")),
    };

    Ok(LocalArtwork {
        mime_type: mime_type.to_string(),
        data_base64: base64::engine::general_purpose::STANDARD.encode(&data),
    })
}

/// The first embedded picture, for the one file the UI is about to show.
#[tauri::command]
fn local_audio_artwork(path: String) -> Result<Option<LocalArtwork>, CommandError> {
    use base64::Engine;
    use lofty::file::TaggedFileExt;

    let path = PathBuf::from(path);
    if !path.is_file() || !is_local_audio_file(&path) {
        return Err(cache_error("local audio file is unavailable."));
    }

    let tagged = lofty::read_from_path(&path)
        .map_err(|error| cache_error(format!("tag read failed: {error}")))?;
    let Some(tag) = tagged.primary_tag().or_else(|| tagged.first_tag()) else {
        return Ok(None);
    };
    let Some(picture) = tag.pictures().first() else {
        return Ok(None);
    };

    Ok(Some(LocalArtwork {
        mime_type: picture
            .mime_type()
            .map(|mime| mime.to_string())
            .unwrap_or_else(|| "image/jpeg".to_string()),
        data_base64: base64::engine::general_purpose::STANDARD.encode(picture.data()),
    }))
}

fn scan_local_audio_path(path: &Path, files: &mut Vec<LocalAudioFile>) -> Result<(), CommandError> {
    let metadata = match fs::metadata(path) {
        Ok(metadata) => metadata,
        Err(_) => return Ok(()),
    };

    if metadata.is_file() {
        if is_local_audio_file(path) {
            files.push(local_audio_entry(path));
        }
        return Ok(());
    }

    if !metadata.is_dir() {
        return Ok(());
    }

    let entries = fs::read_dir(path).map_err(|error| CommandError {
        message: format!("local audio directory read failed: {error}"),
    })?;

    for entry in entries.flatten() {
        scan_local_audio_path(&entry.path(), files)?;
    }

    Ok(())
}

#[tauri::command]
fn local_audio_scan(paths: Vec<String>) -> Result<Vec<LocalAudioFile>, CommandError> {
    let mut files = Vec::new();
    for path in paths {
        let trimmed_path = path.trim();
        if trimmed_path.is_empty() {
            continue;
        }
        scan_local_audio_path(Path::new(trimmed_path), &mut files)?;
    }
    files.sort_by(|left, right| left.path.to_lowercase().cmp(&right.path.to_lowercase()));
    files.dedup_by(|left, right| left.path == right.path);
    Ok(files)
}

#[derive(Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
struct LocalAudioTags {
    title: Option<String>,
    artist: Option<String>,
    album: Option<String>,
    album_artist: Option<String>,
    genre: Option<String>,
    track_number: Option<u32>,
    year: Option<u32>,
    /// Write-only: absent means leave the existing cover alone. See `ArtworkEdit`.
    #[serde(default, skip_serializing)]
    artwork: Option<ArtworkEdit>,
}

/**
 * What to do with the file's cover on save.
 *
 * Three states, not two. A plain `Option<Picture>` could only say "set this" or "remove it",
 * so every save from a dialog the user never touched the artwork in would rewrite or delete a
 * cover they meant to keep.
 */
#[derive(Deserialize)]
#[serde(rename_all = "camelCase", tag = "kind")]
enum ArtworkEdit {
    Keep,
    Remove,
    Replace {
        mime_type: String,
        data_base64: String,
    },
}

/// Cover art is embedded in the file, so an unreasonable one bloats every copy of the song.
const MAX_ARTWORK_BYTES: usize = 12 * 1024 * 1024;

/// Reads real tags from a file.
///
/// The scanner falls back to the filename and parent folder, which is fine for a quick list
/// but wrong often enough that an editor needs the actual values — otherwise "save" would
/// write the guessed name back into the file as if it were the truth.
/// Reads a user-chosen text file. Used for playlist import.
///
/// Size-capped: the picker lets someone choose any file at all, and reading a multi-gigabyte
/// one into a string to discover it is not a playlist would take the app down with it.
#[tauri::command]
fn read_text_file(path: String) -> Result<String, CommandError> {
    const MAX_IMPORT_BYTES: u64 = 16 * 1024 * 1024;

    let path = playlist_file_path(path)?;
    let metadata = fs::metadata(&path)
        .map_err(|error| cache_error(format!("file read failed: {error}")))?;
    if metadata.len() > MAX_IMPORT_BYTES {
        return Err(cache_error("that file is too large to be a playlist"));
    }

    fs::read_to_string(&path).map_err(|error| cache_error(format!("file read failed: {error}")))
}

/// Writes a user-chosen text file. Used for playlist export.
#[tauri::command]
fn write_text_file(path: String, contents: String) -> Result<(), CommandError> {
    let path = playlist_file_path(path)?;
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)
            .map_err(|error| cache_error(format!("directory creation failed: {error}")))?;
    }
    fs::write(&path, contents).map_err(|error| cache_error(format!("file write failed: {error}")))
}

/// Only the playlist files that import and export handle (JSON and M3U): whatever the page asks
/// for, these two commands never read or write a shell profile, an autostart entry or any other
/// file that could run code or hold secrets.
fn playlist_file_path(path: String) -> Result<PathBuf, CommandError> {
    let path = PathBuf::from(path);
    let extension = path
        .extension()
        .and_then(|extension| extension.to_str())
        .map(str::to_ascii_lowercase);
    match extension.as_deref() {
        Some("json" | "m3u" | "m3u8") => Ok(path),
        _ => Err(cache_error("only JSON and M3U playlist files can be read or written")),
    }
}

#[tauri::command]
fn local_audio_read_tags(path: String) -> Result<LocalAudioTags, CommandError> {
    use lofty::file::TaggedFileExt;
    use lofty::tag::Accessor;

    let path = PathBuf::from(path);
    if !path.is_file() || !is_local_audio_file(&path) {
        return Err(cache_error("local audio file is unavailable."));
    }

    let tagged = lofty::read_from_path(&path)
        .map_err(|error| cache_error(format!("tag read failed: {error}")))?;
    let Some(tag) = tagged.primary_tag().or_else(|| tagged.first_tag()) else {
        return Ok(LocalAudioTags::default());
    };

    Ok(LocalAudioTags {
        title: tag.title().map(|value| value.to_string()),
        artist: tag.artist().map(|value| value.to_string()),
        album: tag.album().map(|value| value.to_string()),
        album_artist: tag
            .get_string(lofty::tag::ItemKey::AlbumArtist)
            .map(|value| value.to_string()),
        genre: tag.genre().map(|value| value.to_string()),
        track_number: tag.track(),
        // Year lives under a plain item key rather than an Accessor method in lofty 0.24.
        year: tag
            .get_string(lofty::tag::ItemKey::Year)
            .and_then(|value| value.trim().get(..4).and_then(|text| text.parse().ok())),
        artwork: None,
    })
}

#[tauri::command]
fn local_audio_write_tags(path: String, tags: LocalAudioTags) -> Result<(), CommandError> {
    use lofty::config::WriteOptions;
    use lofty::file::{AudioFile, TaggedFileExt};
    use lofty::tag::{Accessor, ItemKey, Tag};

    let path = PathBuf::from(path);
    if !path.is_file() || !is_local_audio_file(&path) {
        return Err(cache_error("local audio file is unavailable."));
    }

    let mut tagged = lofty::read_from_path(&path)
        .map_err(|error| cache_error(format!("tag read failed: {error}")))?;

    // A file with no tag at all still needs somewhere to put these, so one is created in the
    // format that file type expects rather than failing the edit.
    let tag_type = tagged.primary_tag_type();
    if tagged.primary_tag().is_none() {
        tagged.insert_tag(Tag::new(tag_type));
    }
    let Some(tag) = tagged.primary_tag_mut() else {
        return Err(cache_error("this file cannot store tags"));
    };

    fn apply(tag: &mut Tag, key: ItemKey, value: Option<&String>) {
        match value.map(|text| text.trim()).filter(|text| !text.is_empty()) {
            // An empty field is an instruction to clear the tag, not to leave it alone.
            Some(text) => {
                let _ = tag.insert_text(key, text.to_string());
            }
            None => {
                let _ = tag.remove_key(key);
            }
        }
    }

    apply(tag, ItemKey::TrackTitle, tags.title.as_ref());
    apply(tag, ItemKey::TrackArtist, tags.artist.as_ref());
    apply(tag, ItemKey::AlbumTitle, tags.album.as_ref());
    apply(tag, ItemKey::AlbumArtist, tags.album_artist.as_ref());
    apply(tag, ItemKey::Genre, tags.genre.as_ref());

    match tags.track_number {
        Some(number) => tag.set_track(number),
        None => tag.remove_track(),
    }
    match tags.year {
        Some(year) => {
            let _ = tag.insert_text(ItemKey::Year, year.to_string());
        }
        None => {
            let _ = tag.remove_key(ItemKey::Year);
        }
    }

    match tags.artwork {
        None | Some(ArtworkEdit::Keep) => {}
        Some(ArtworkEdit::Remove) => {
            // Every picture, not just the front cover: leaving a stray back-cover or artist
            // shot behind is what makes a "removed" cover reappear somewhere else.
            while !tag.pictures().is_empty() {
                let _ = tag.remove_picture(0);
            }
        }
        Some(ArtworkEdit::Replace {
            mime_type,
            data_base64,
        }) => {
            use base64::Engine;
            use lofty::picture::{MimeType, Picture, PictureType};

            let data = base64::engine::general_purpose::STANDARD
                .decode(data_base64.as_bytes())
                .map_err(|error| cache_error(format!("artwork decode failed: {error}")))?;
            if data.is_empty() {
                return Err(cache_error("that image is empty"));
            }
            if data.len() > MAX_ARTWORK_BYTES {
                return Err(cache_error("that image is too large to embed"));
            }

            while !tag.pictures().is_empty() {
                let _ = tag.remove_picture(0);
            }
            tag.push_picture(
                Picture::unchecked(data)
                    .pic_type(PictureType::CoverFront)
                    .mime_type(MimeType::from_str(&mime_type))
                    .build(),
            );
        }
    }

    tagged
        .save_to_path(&path, WriteOptions::default())
        .map_err(|error| cache_error(format!("tag write failed: {error}")))?;

    eprintln!(
        "[internal][tauri][info] local_audio_write_tags path={}",
        path.display()
    );
    Ok(())
}

/// Holds the active folder watcher. Replaced wholesale whenever the watched set changes.
struct LocalAudioWatcher(Mutex<Option<notify::RecommendedWatcher>>);

/// Watches folders for changes and tells the frontend to rescan.
///
/// Deliberately coarse: it emits one debounced "something changed" event rather than a diff.
/// The scan is cheap, and a precise change feed would have to model renames, temp files and
/// editors that write-then-replace — all of which produce the same user-visible outcome.
#[tauri::command]
fn local_audio_watch(
    app: tauri::AppHandle,
    state: tauri::State<'_, LocalAudioWatcher>,
    paths: Vec<String>,
) -> Result<(), CommandError> {
    use notify::{RecursiveMode, Watcher};

    let mut guard = state
        .0
        .lock()
        .map_err(|_| cache_error("watcher lock unavailable"))?;
    // Dropping the previous watcher unregisters every path it held.
    *guard = None;

    if paths.is_empty() {
        return Ok(());
    }

    let emitter = app.clone();
    let last_emit = Arc::new(Mutex::new(Instant::now() - Duration::from_secs(60)));
    let mut watcher = notify::recommended_watcher(move |event: notify::Result<notify::Event>| {
        let Ok(event) = event else { return };
        if !matches!(
            event.kind,
            notify::EventKind::Create(_) | notify::EventKind::Remove(_) | notify::EventKind::Modify(_)
        ) {
            return;
        }

        // A single save can fire several events; one rescan per second is plenty.
        if let Ok(mut last) = last_emit.lock() {
            if last.elapsed() < Duration::from_millis(1000) {
                return;
            }
            *last = Instant::now();
        }
        let _ = emitter.emit("local-audio-changed", ());
    })
    .map_err(|error| cache_error(format!("watcher creation failed: {error}")))?;

    for path in &paths {
        let candidate = Path::new(path.trim());
        if !candidate.exists() {
            continue;
        }
        if let Err(error) = watcher.watch(candidate, RecursiveMode::Recursive) {
            eprintln!(
                "[internal][tauri][warn] local_audio_watch failed path={} error={}",
                path, error
            );
        }
    }

    *guard = Some(watcher);
    eprintln!(
        "[internal][tauri][info] local_audio_watch watching {} paths",
        paths.len()
    );
    Ok(())
}

fn cache_root(app: &tauri::AppHandle) -> Result<PathBuf, CommandError> {
    app.path()
        .app_cache_dir()
        .map(|path| path.join("data-cache-v1"))
        .map_err(|error| cache_error(format!("cache directory unavailable: {error}")))
}

fn cache_entries_dir(app: &tauri::AppHandle) -> Result<PathBuf, CommandError> {
    Ok(cache_root(app)?.join("entries"))
}

fn cache_settings_path(app: &tauri::AppHandle) -> Result<PathBuf, CommandError> {
    Ok(cache_root(app)?.join("settings.json"))
}

fn now_ms() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis() as u64
}

fn cache_key_hash(key: &str) -> u64 {
    let mut hash = 0xcbf29ce484222325_u64;
    for byte in key.as_bytes() {
        hash ^= u64::from(*byte);
        hash = hash.wrapping_mul(0x100000001b3);
    }
    hash
}

fn cache_entry_path(app: &tauri::AppHandle, key: &str) -> Result<PathBuf, CommandError> {
    Ok(cache_entries_dir(app)?.join(format!("{:016x}.json", cache_key_hash(key))))
}

fn write_json_file<T: Serialize>(path: &Path, value: &T) -> Result<(), CommandError> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)
            .map_err(|error| cache_error(format!("cache directory creation failed: {error}")))?;
    }
    let bytes = serde_json::to_vec(value)
        .map_err(|error| cache_error(format!("cache serialization failed: {error}")))?;
    let temp_path = path.with_extension("tmp");
    fs::write(&temp_path, bytes)
        .map_err(|error| cache_error(format!("cache write failed: {error}")))?;
    if path.exists() {
        fs::remove_file(path)
            .map_err(|error| cache_error(format!("cache replacement failed: {error}")))?;
    }
    fs::rename(&temp_path, path)
        .map_err(|error| cache_error(format!("cache finalize failed: {error}")))
}

fn app_settings_path(app: &tauri::AppHandle) -> Result<PathBuf, CommandError> {
    app.path()
        .app_data_dir()
        .map(|path| path.join(APP_SETTINGS_FILE_NAME))
        .map_err(|error| CommandError {
            message: format!("application settings directory unavailable: {error}"),
        })
}

fn read_app_settings(
    app: &tauri::AppHandle,
) -> Result<HashMap<String, serde_json::Value>, CommandError> {
    let path = app_settings_path(app)?;
    if !path.exists() {
        return Ok(HashMap::new());
    }

    let bytes = fs::read(path).map_err(|error| CommandError {
        message: format!("application settings read failed: {error}"),
    })?;
    if bytes.iter().all(|byte| byte.is_ascii_whitespace()) {
        return Ok(HashMap::new());
    }
    serde_json::from_slice(&bytes).map_err(|error| CommandError {
        message: format!("application settings parse failed: {error}"),
    })
}

#[tauri::command]
fn app_setting_get(
    app: tauri::AppHandle,
    lock: tauri::State<'_, AppSettingsLock>,
    key: String,
) -> Result<Option<serde_json::Value>, CommandError> {
    let _guard = lock.0.lock().map_err(|_| CommandError {
        message: "application settings lock unavailable".to_string(),
    })?;
    Ok(read_app_settings(&app)?.remove(&key))
}

#[tauri::command]
fn app_setting_set(
    app: tauri::AppHandle,
    lock: tauri::State<'_, AppSettingsLock>,
    key: String,
    value: serde_json::Value,
) -> Result<(), CommandError> {
    let _guard = lock.0.lock().map_err(|_| CommandError {
        message: "application settings lock unavailable".to_string(),
    })?;
    let mut settings = read_app_settings(&app)?;
    settings.insert(key, value);
    write_json_file(&app_settings_path(&app)?, &settings)
}

#[tauri::command]
fn app_setting_remove(
    app: tauri::AppHandle,
    lock: tauri::State<'_, AppSettingsLock>,
    key: String,
) -> Result<(), CommandError> {
    let _guard = lock.0.lock().map_err(|_| CommandError {
        message: "application settings lock unavailable".to_string(),
    })?;
    let mut settings = read_app_settings(&app)?;
    settings.remove(&key);
    write_json_file(&app_settings_path(&app)?, &settings)
}

fn current_log_path(app: &tauri::AppHandle) -> Result<PathBuf, CommandError> {
    app.path()
        .app_log_dir()
        .map(|path| path.join(CURRENT_LOG_FILE_NAME))
        .map_err(|error| CommandError {
            message: format!("log directory unavailable: {error}"),
        })
}

fn initialize_app_log(app: &tauri::AppHandle) -> Result<(), CommandError> {
    let log_path = current_log_path(app)?;
    let log_dir = log_path.parent().ok_or_else(|| CommandError {
        message: "log directory unavailable".to_string(),
    })?;

    fs::create_dir_all(log_dir).map_err(|error| CommandError {
        message: format!("log directory creation failed: {error}"),
    })?;

    if let Ok(entries) = fs::read_dir(log_dir) {
        for entry in entries.flatten() {
            let path = entry.path();
            if path != log_path
                && path
                    .extension()
                    .is_some_and(|extension| extension.eq_ignore_ascii_case("log"))
            {
                let _ = fs::remove_file(path);
            }
        }
    }

    let file = OpenOptions::new()
        .create(true)
        .write(true)
        .truncate(true)
        .open(&log_path)
        .map_err(|error| CommandError {
            message: format!("log file creation failed: {error}"),
        })?;

    let log_file = APP_LOG_FILE.get_or_init(|| Mutex::new(None));
    if let Ok(mut guard) = log_file.lock() {
        *guard = Some(file);
    }

    append_log_line(format_args!(
        "[internal][tauri][info] log initialized path={}",
        log_path.display()
    ));
    Ok(())
}

pub(crate) fn append_log_line(args: fmt::Arguments<'_>) {
    let Some(log_file) = APP_LOG_FILE.get() else {
        return;
    };
    let Ok(mut guard) = log_file.lock() else {
        return;
    };
    let Some(file) = guard.as_mut() else {
        return;
    };
    let _ = writeln!(file, "{args}");
}

pub(crate) fn sanitize_log_message(message: &str) -> String {
    message
        .split_whitespace()
        .map(sanitize_log_token)
        .collect::<Vec<_>>()
        .join(" ")
}

fn sanitize_log_token(token: &str) -> String {
    if let Some((key, value)) = token.split_once('=') {
        let normalized_key = key
            .trim_matches(|character: char| !character.is_ascii_alphanumeric() && character != '_')
            .to_ascii_lowercase();
        if normalized_key.contains("cookie")
            || normalized_key.contains("authorization")
            || normalized_key.contains("credential")
            || normalized_key.contains("token")
            || normalized_key.contains("secret")
            || normalized_key.contains("password")
            || normalized_key.contains("signature")
            || normalized_key.contains("cipher")
            || normalized_key.contains("visitor")
        {
            return format!("{key}=[redacted]");
        }
        if value.starts_with("http://") || value.starts_with("https://") {
            return format!("{key}={}", sanitize_log_url(value));
        }
    }

    if token.starts_with("http://") || token.starts_with("https://") {
        return sanitize_log_url(token);
    }

    token.to_string()
}

/// Query parameters kept verbatim when a URL is logged.
///
/// An allowlist, not a blocklist: googlevideo grows new parameters constantly and a blocklist
/// would silently start writing down the next credential it invents. Everything here is
/// descriptive — expiry, format, size, client identity — and none of it authenticates anything.
const LOGGABLE_URL_PARAMS: &[&str] = &[
    "expire", "id", "itag", "source", "mime", "clen", "dur", "lmt", "c", "cver", "mn", "ms",
    "mv", "mt", "fvip", "keepalive", "ratebypass", "requiressl", "gir", "sq", "rn", "ver",
    "xpc", "spc", "vprv", "svpuc", "txp", "range", "met", "rqh", "aitags", "sabr", "pcm2",
];

/// Renders a URL for the log with its credentials removed but its diagnostics intact.
///
/// The previous behaviour dropped the whole query string, which made a signed media URL
/// unreadable — the parameters that explain a 403 (expiry, itag, client version) were discarded
/// alongside the ones that must never be written down. Withheld values are replaced by their
/// length, which answers the question actually being asked of them ("is it present and
/// plausible, or missing and truncated?") without recording the secret itself.
fn sanitize_log_url(value: &str) -> String {
    let Ok(parsed) = url::Url::parse(value) else {
        return "[redacted-url]".to_string();
    };

    let base = format!(
        "{}://{}{}",
        parsed.scheme(),
        parsed.host_str().unwrap_or("?"),
        parsed.path()
    );

    let query: Vec<String> = parsed
        .query_pairs()
        .map(|(key, value)| {
            if LOGGABLE_URL_PARAMS.contains(&key.as_ref()) {
                format!("{key}={value}")
            } else {
                format!("{key}=[{}ch]", value.len())
            }
        })
        .collect();

    if query.is_empty() {
        base
    } else {
        format!("{base}?{}", query.join("&"))
    }
}

#[tauri::command]
fn open_current_log(app: tauri::AppHandle) -> Result<(), CommandError> {
    let log_path = current_log_path(&app)?;
    if !log_path.exists() {
        initialize_app_log(&app)?;
    }
    tauri_plugin_opener::open_path(&log_path, None::<&str>).map_err(|error| CommandError {
        message: format!("unable to open log file: {error}"),
    })
}

#[tauri::command]
fn app_settings_clear(
    app: tauri::AppHandle,
    lock: tauri::State<'_, AppSettingsLock>,
) -> Result<(), CommandError> {
    let _guard = lock.0.lock().map_err(|_| CommandError {
        message: "application settings lock unavailable".to_string(),
    })?;
    let path = app_settings_path(&app)?;
    if path.exists() {
        fs::remove_file(path).map_err(|error| CommandError {
            message: format!("application settings clear failed: {error}"),
        })?;
    }
    Ok(())
}

fn read_cache_settings(app: &tauri::AppHandle) -> Result<CacheSettings, CommandError> {
    let path = cache_settings_path(app)?;
    if !path.exists() {
        return Ok(CacheSettings {
            max_bytes: DEFAULT_CACHE_MAX_BYTES,
        });
    }
    let bytes = fs::read(path)
        .map_err(|error| cache_error(format!("cache settings read failed: {error}")))?;
    serde_json::from_slice(&bytes)
        .map_err(|error| cache_error(format!("cache settings parse failed: {error}")))
}

fn cache_files(app: &tauri::AppHandle) -> Result<Vec<PathBuf>, CommandError> {
    let directory = cache_entries_dir(app)?;
    if !directory.exists() {
        return Ok(Vec::new());
    }
    let files = fs::read_dir(directory)
        .map_err(|error| cache_error(format!("cache directory read failed: {error}")))?
        .filter_map(|entry| entry.ok().map(|entry| entry.path()))
        .filter(|path| {
            path.extension()
                .is_some_and(|extension| extension == "json")
        })
        .collect::<Vec<_>>();
    Ok(files)
}

fn read_cache_entry(path: &Path) -> Result<CacheEntry, CommandError> {
    let bytes =
        fs::read(path).map_err(|error| cache_error(format!("cache entry read failed: {error}")))?;
    serde_json::from_slice(&bytes)
        .map_err(|error| cache_error(format!("cache entry parse failed: {error}")))
}

fn calculate_cache_stats(app: &tauri::AppHandle) -> Result<CacheStats, CommandError> {
    let files = cache_files(app)?;
    let used_bytes = files
        .iter()
        .filter_map(|path| fs::metadata(path).ok().map(|metadata| metadata.len()))
        .sum();
    Ok(CacheStats {
        max_bytes: read_cache_settings(app)?.max_bytes,
        used_bytes,
        entry_count: files.len(),
    })
}

fn enforce_cache_limit(app: &tauri::AppHandle) -> Result<(), CommandError> {
    let max_bytes = read_cache_settings(app)?.max_bytes;
    let mut entries = cache_files(app)?
        .into_iter()
        .filter_map(|path| {
            let size = fs::metadata(&path).ok()?.len();
            let last_accessed_ms = read_cache_entry(&path).ok()?.last_accessed_ms;
            Some((path, size, last_accessed_ms))
        })
        .collect::<Vec<_>>();
    let mut used_bytes = entries.iter().map(|(_, size, _)| *size).sum::<u64>();
    entries.sort_by_key(|(_, _, last_accessed_ms)| *last_accessed_ms);

    for (path, size, _) in entries {
        if used_bytes <= max_bytes {
            break;
        }
        if fs::remove_file(path).is_ok() {
            used_bytes = used_bytes.saturating_sub(size);
        }
    }
    Ok(())
}

#[tauri::command]
fn cache_get(
    app: tauri::AppHandle,
    lock: tauri::State<'_, CacheLock>,
    key: String,
) -> Result<Option<String>, CommandError> {
    let _guard = lock
        .0
        .lock()
        .map_err(|_| cache_error("cache lock unavailable"))?;
    let path = cache_entry_path(&app, &key)?;
    if !path.exists() {
        return Ok(None);
    }
    let mut entry = match read_cache_entry(&path) {
        Ok(entry) if entry.key == key => entry,
        Ok(_) => return Ok(None),
        Err(_) => {
            let _ = fs::remove_file(path);
            return Ok(None);
        }
    };
    entry.last_accessed_ms = now_ms();
    let value = entry.value.clone();
    write_json_file(&path, &entry)?;
    Ok(Some(value))
}

#[tauri::command]
fn cache_set(
    app: tauri::AppHandle,
    lock: tauri::State<'_, CacheLock>,
    key: String,
    value: String,
) -> Result<CacheWriteResult, CommandError> {
    let _guard = lock
        .0
        .lock()
        .map_err(|_| cache_error("cache lock unavailable"))?;
    let path = cache_entry_path(&app, &key)?;
    let existing = if path.exists() {
        read_cache_entry(&path)
            .ok()
            .filter(|entry| entry.key == key)
    } else {
        None
    };
    let changed = existing.as_ref().map_or(true, |entry| entry.value != value);
    let timestamp = now_ms();
    let entry = CacheEntry {
        key,
        value,
        updated_at_ms: if changed {
            timestamp
        } else {
            existing
                .as_ref()
                .map(|entry| entry.updated_at_ms)
                .unwrap_or(timestamp)
        },
        last_accessed_ms: timestamp,
    };
    write_json_file(&path, &entry)?;
    enforce_cache_limit(&app)?;
    Ok(CacheWriteResult { changed })
}

#[tauri::command]
fn cache_stats(
    app: tauri::AppHandle,
    lock: tauri::State<'_, CacheLock>,
) -> Result<CacheStats, CommandError> {
    let _guard = lock
        .0
        .lock()
        .map_err(|_| cache_error("cache lock unavailable"))?;
    calculate_cache_stats(&app)
}

#[tauri::command]
fn cache_set_max_bytes(
    app: tauri::AppHandle,
    lock: tauri::State<'_, CacheLock>,
    max_bytes: u64,
) -> Result<CacheStats, CommandError> {
    let _guard = lock
        .0
        .lock()
        .map_err(|_| cache_error("cache lock unavailable"))?;
    write_json_file(&cache_settings_path(&app)?, &CacheSettings { max_bytes })?;
    enforce_cache_limit(&app)?;
    calculate_cache_stats(&app)
}

#[tauri::command]
fn cache_clear(
    app: tauri::AppHandle,
    lock: tauri::State<'_, CacheLock>,
) -> Result<CacheStats, CommandError> {
    let _guard = lock
        .0
        .lock()
        .map_err(|_| cache_error("cache lock unavailable"))?;
    let entries = cache_entries_dir(&app)?;
    if entries.exists() {
        fs::remove_dir_all(&entries)
            .map_err(|error| cache_error(format!("cache clear failed: {error}")))?;
    }
    fs::create_dir_all(entries)
        .map_err(|error| cache_error(format!("cache directory creation failed: {error}")))?;
    calculate_cache_stats(&app)
}


fn show_main_window(app: &tauri::AppHandle) {
    if let Some(window) = app.get_webview_window("main") {
        let _ = window.show();
        let _ = window.unminimize();
        let _ = window.set_focus();
    }
}

#[tauri::command]
fn frontend_log(level: String, context: String, payload: String) {
    eprintln!("[internal][frontend][{}] {} {}", level, context, payload);
}

fn youtube_keyring_entry() -> Result<keyring::Entry, CommandError> {
    keyring::Entry::new(KEYRING_SERVICE, KEYRING_USER).map_err(|error| CommandError {
        message: format!("credential store unavailable: {error}"),
    })
}

fn youtube_cookie_keyring_entry() -> Result<keyring::Entry, CommandError> {
    keyring::Entry::new(KEYRING_SERVICE, YOUTUBE_COOKIE_KEYRING_USER).map_err(|error| {
        CommandError {
            message: format!("credential store unavailable: {error}"),
        }
    })
}

fn youtube_cookie_chunk_entry(index: usize) -> Result<keyring::Entry, CommandError> {
    keyring::Entry::new(
        KEYRING_SERVICE,
        &format!("{YOUTUBE_COOKIE_KEYRING_USER}-{index}"),
    )
    .map_err(|error| CommandError {
        message: format!("credential store unavailable: {error}"),
    })
}

/// One save at a time: two cookie rotations persisting at once interleaved their keyring calls.
static YOUTUBE_COOKIE_STORE_LOCK: Mutex<()> = Mutex::new(());

/// How many chunks an older save left behind its `chunks:N` manifest; `0` for a single entry or
/// for none at all.
fn stored_youtube_cookie_chunk_count() -> Result<usize, CommandError> {
    match youtube_cookie_keyring_entry()?.get_password() {
        Ok(manifest) if manifest.starts_with("chunks:") => Ok(manifest
            .trim_start_matches("chunks:")
            .parse::<usize>()
            .unwrap_or(YOUTUBE_COOKIE_MAX_CHUNKS)
            .min(YOUTUBE_COOKIE_MAX_CHUNKS)),
        Ok(_) | Err(keyring::Error::NoEntry) => Ok(0),
        Err(error) => Err(CommandError {
            message: format!("YouTube Music session load failed: {error}"),
        }),
    }
}

/**
 * The whole blob in one keyring entry, written in one call.
 *
 * It used to be split into 900-byte chunks, a limit of other platforms' credential stores and not
 * of the Secret Service, and every save deleted all 64 chunk slots before writing each chunk
 * again: 70 to 130 Secret Service sessions in a burst, on nearly every cookie rotation.
 * gnome-keyring aborted in the middle of one, and the session being saved never reached the
 * disk, so the next launch was signed out. `load_youtube_music_cookie_entries` has always read a
 * single entry; the chunks an older save left are removed once, after the entry is written.
 */
fn save_youtube_music_cookie_entries(cookie: &str) -> Result<(), CommandError> {
    if cookie.len() > YOUTUBE_COOKIE_CHUNK_SIZE * YOUTUBE_COOKIE_MAX_CHUNKS {
        return Err(CommandError {
            message: "YouTube Music session is too large for secure storage.".to_string(),
        });
    }

    let _storing = YOUTUBE_COOKIE_STORE_LOCK
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    let old_chunks = stored_youtube_cookie_chunk_count()?;
    eprintln!(
        "[internal][tauri][info] save_youtube_music_cookie bytes={} old_chunks={}",
        cookie.len(),
        old_chunks
    );
    youtube_cookie_keyring_entry()?
        .set_password(cookie)
        .map_err(|error| CommandError {
            message: format!("YouTube Music session save failed: {error}"),
        })?;
    // The session is saved by now; a chunk that won't go only takes up room
    for index in 0..old_chunks {
        match youtube_cookie_chunk_entry(index).map(|entry| entry.delete_credential()) {
            Ok(Ok(())) | Ok(Err(keyring::Error::NoEntry)) => {}
            Ok(Err(error)) => eprintln!(
                "[internal][tauri][warn] save_youtube_music_cookie old chunk {index} delete failed: {error}"
            ),
            Err(error) => eprintln!(
                "[internal][tauri][warn] save_youtube_music_cookie old chunk {index} delete failed: {}",
                error.message
            ),
        }
    }
    Ok(())
}





fn save_youtube_music_cookie(_app: &tauri::AppHandle, cookie: &str) -> Result<(), CommandError> {
    save_youtube_music_cookie_entries(cookie)
}

/// Clears the OAuth credential left behind by the version of the app that used one.
///
/// Nothing writes that entry any more — sign-in is entirely cookie-based — but an install old
/// enough to predate the change may still be holding one in the keyring. Removing it on sign-out
/// is the only reason this key is still known about; there is no command for it, because a
/// command implies a second way of being signed in and there is no such thing.
fn delete_legacy_youtube_credentials() {
    if let Ok(entry) = youtube_keyring_entry() {
        match entry.delete_credential() {
            Ok(()) => eprintln!("[internal][tauri][info] removed legacy OAuth credential"),
            Err(keyring::Error::NoEntry) => {}
            Err(error) => eprintln!(
                "[internal][tauri][warn] legacy OAuth credential delete failed: {error}"
            ),
        }
    }
}

fn load_youtube_music_cookie_entries() -> Result<Option<String>, CommandError> {
    match youtube_cookie_keyring_entry()?.get_password() {
        Ok(manifest) if manifest.starts_with("chunks:") => {
            let chunk_count = manifest
                .trim_start_matches("chunks:")
                .parse::<usize>()
                .map_err(|error| CommandError {
                    message: format!("invalid YouTube Music session manifest: {error}"),
                })?;
            if chunk_count == 0 || chunk_count > YOUTUBE_COOKIE_MAX_CHUNKS {
                return Err(CommandError {
                    message: "invalid YouTube Music session chunk count.".to_string(),
                });
            }

            let mut cookie = String::new();
            for index in 0..chunk_count {
                let chunk = youtube_cookie_chunk_entry(index)?
                    .get_password()
                    .map_err(|error| CommandError {
                        message: format!(
                            "YouTube Music session chunk {index} load failed: {error}"
                        ),
                    })?;
                cookie.push_str(&chunk);
            }
            eprintln!(
                "[internal][tauri][info] load_youtube_music_cookie assembled chunks={} bytes={}",
                chunk_count,
                cookie.len(),
            );
            Ok(Some(cookie))
        }
        // One entry: how every save writes it now (and how the oldest versions did)
        Ok(cookie) => {
            eprintln!(
                "[internal][tauri][info] load_youtube_music_cookie found credential bytes={}",
                cookie.len()
            );
            Ok(Some(cookie))
        }
        Err(keyring::Error::NoEntry) => {
            eprintln!("[internal][tauri][info] load_youtube_music_cookie no credential");
            Ok(None)
        }
        Err(error) => Err(CommandError {
            message: format!("YouTube Music session load failed: {error}"),
        }),
    }
}

/// Loads the account store, transparently migrating a pre-multi-account install's bare cookie
/// header into it the first time it is read.
///
/// The migration is persisted immediately (pinned to `LEGACY_ACCOUNT_SLOT_ID`, not a random id)
/// so it happens once, not on every call — and so every other command sees an ordinary
/// multi-account store from then on, never the legacy shape.
fn load_account_store(app: &tauri::AppHandle) -> Result<YoutubeAccountStore, CommandError> {
    let Some(blob) = load_youtube_music_cookie_entries()? else {
        return Ok(YoutubeAccountStore::default());
    };
    match serde_json::from_str::<YoutubeAccountStore>(&blob) {
        Ok(store) => Ok(store),
        Err(_) => {
            let migrated = YoutubeAccountStore::from_legacy_cookie(&blob, LEGACY_ACCOUNT_SLOT_ID.to_string());
            match save_account_store(app, &migrated) {
                Ok(()) => eprintln!(
                    "[internal][tauri][info] migrated legacy single-account session to the multi-account store"
                ),
                Err(error) => eprintln!(
                    "[internal][tauri][warn] could not persist migrated account store: {}",
                    error.message
                ),
            }
            Ok(migrated)
        }
    }
}

fn save_account_store(app: &tauri::AppHandle, store: &YoutubeAccountStore) -> Result<(), CommandError> {
    let json = serde_json::to_string(store).map_err(|error| CommandError {
        message: format!("account store encode failed: {error}"),
    })?;
    save_youtube_music_cookie(app, &json)
}

/// Writes one slot's cookie into the durable store only — the live in-memory jar is untouched.
/// Used by the cookie-rotation path in `refresh_youtube_cookie_jar`, which has already updated
/// the jar itself and would otherwise redo that work.
fn persist_account_cookie(
    app: &tauri::AppHandle,
    account_lock: &AccountStoreLock,
    slot_id: &str,
    cookie: &str,
) -> Result<(), CommandError> {
    let _guard = account_lock.0.lock().map_err(|_| CommandError {
        message: "account store lock unavailable".to_string(),
    })?;
    let mut store = load_account_store(app)?;
    let Some(account) = store.accounts.iter_mut().find(|account| account.slot_id == slot_id) else {
        // Removed mid-flight (e.g. from another window) — nothing durable left to update.
        return Ok(());
    };
    account.cookie = cookie.to_string();
    if account.identity.is_none() {
        account.identity = cookie_account_identity(cookie);
    }
    save_account_store(app, &store)
}

/// `persist_account_cookie`, plus updating the live jar — for callers (silent renewal) that
/// have not already updated it themselves.
fn persist_active_account_cookie(
    app: &tauri::AppHandle,
    account_lock: &AccountStoreLock,
    jar: &YoutubeCookieJar,
    slot_id: &str,
    cookie: &str,
) -> Result<(), CommandError> {
    persist_account_cookie(app, account_lock, slot_id, cookie)?;
    if let Ok(mut state) = jar.0.lock() {
        state.cookie = Some(cookie.to_string());
        state.persisted_at = Some(Instant::now());
    }
    Ok(())
}

/// Removes one stored account and, when it was active, falls the active slot back to another
/// stored account if any remain. Shared by `delete_youtube_music_cookie` (removes whichever is
/// active — today's "sign out") and `remove_youtube_music_account` (removes a specific one).
fn remove_account_slot(
    app: &tauri::AppHandle,
    account_lock: &AccountStoreLock,
    jar: &YoutubeCookieJar,
    slot_id: &str,
) -> Result<Option<String>, CommandError> {
    let (new_active_cookie, existed) = {
        let _guard = account_lock.0.lock().map_err(|_| CommandError {
            message: "account store lock unavailable".to_string(),
        })?;
        let mut store = load_account_store(app)?;
        let result = store.remove(slot_id);
        save_account_store(app, &store)?;
        result
    };
    if existed {
        // Idempotent and cheap; sign-out has always swept this pre-cookie-auth leftover too.
        delete_legacy_youtube_credentials();
        remove_login_partition(app, slot_id);
    }
    if let Ok(mut state) = jar.0.lock() {
        state.cookie = new_active_cookie.clone();
        state.persisted_at = new_active_cookie.as_ref().map(|_| Instant::now());
    }
    Ok(new_active_cookie)
}

#[tauri::command]
fn load_youtube_music_cookie(
    app: tauri::AppHandle,
    jar: tauri::State<'_, YoutubeCookieJar>,
    account_lock: tauri::State<'_, AccountStoreLock>,
) -> Result<Option<String>, CommandError> {
    let _guard = account_lock.0.lock().map_err(|_| CommandError {
        message: "account store lock unavailable".to_string(),
    })?;
    let cookie = load_account_store(&app)?.active().map(|account| account.cookie.clone());
    if let Ok(mut state) = jar.0.lock() {
        state.cookie = cookie.clone();
        state.persisted_at = None;
    }
    Ok(cookie)
}

/// Every stored Google account, for the account switcher. Never includes the identity
/// fingerprint — only `slot_id`, an opaque random id with no information content, crosses into
/// the frontend.
#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct YoutubeAccountSummary {
    slot_id: String,
    name: Option<String>,
    avatar_url: Option<String>,
    is_active: bool,
}

#[tauri::command]
fn list_youtube_music_accounts(
    app: tauri::AppHandle,
    account_lock: tauri::State<'_, AccountStoreLock>,
) -> Result<Vec<YoutubeAccountSummary>, CommandError> {
    let _guard = account_lock.0.lock().map_err(|_| CommandError {
        message: "account store lock unavailable".to_string(),
    })?;
    let store = load_account_store(&app)?;
    Ok(store
        .accounts
        .iter()
        .map(|account| YoutubeAccountSummary {
            slot_id: account.slot_id.clone(),
            name: account.display_name.clone(),
            avatar_url: account.avatar_url.clone(),
            is_active: store.active_slot_id.as_deref() == Some(account.slot_id.as_str()),
        })
        .collect())
}

/// Makes a stored account active without touching the browser at all — the whole point being
/// that this is instant, unlike sign-in.
#[tauri::command]
async fn switch_youtube_music_account(
    app: tauri::AppHandle,
    jar: tauri::State<'_, YoutubeCookieJar>,
    account_lock: tauri::State<'_, AccountStoreLock>,
    slot_id: String,
) -> Result<Option<String>, CommandError> {
    eprintln!("[internal][tauri][info] switch_youtube_music_account slot={slot_id}");
    let cookie = {
        let _guard = account_lock.0.lock().map_err(|_| CommandError {
            message: "account store lock unavailable".to_string(),
        })?;
        let mut store = load_account_store(&app)?;
        let Some(cookie) = store.switch_active(&slot_id) else {
            return Err(CommandError {
                message: "That account is no longer signed in on this device.".to_string(),
            });
        };
        save_account_store(&app, &store)?;
        cookie
    };
    if let Ok(mut state) = jar.0.lock() {
        state.cookie = Some(cookie.clone());
        state.persisted_at = Some(Instant::now());
    }
    Ok(Some(cookie))
}

/// Forgets one stored account. Removing the active one falls back to another stored account
/// automatically, the same as `delete_youtube_music_cookie` — see `remove_account_slot`.
#[tauri::command]
async fn remove_youtube_music_account(
    app: tauri::AppHandle,
    jar: tauri::State<'_, YoutubeCookieJar>,
    account_lock: tauri::State<'_, AccountStoreLock>,
    slot_id: String,
) -> Result<Option<String>, CommandError> {
    eprintln!("[internal][tauri][info] remove_youtube_music_account slot={slot_id}");
    remove_account_slot(&app, &account_lock, &jar, &slot_id)
}

/// Labels a stored account for the switcher UI. Best-effort from the caller's point of view —
/// Rust has no notion of "display name", it only stores whatever the frontend already fetched
/// from YouTube for that account.
#[tauri::command]
fn update_youtube_music_account_profile(
    app: tauri::AppHandle,
    account_lock: tauri::State<'_, AccountStoreLock>,
    slot_id: String,
    name: Option<String>,
    avatar_url: Option<String>,
) -> Result<(), CommandError> {
    let _guard = account_lock.0.lock().map_err(|_| CommandError {
        message: "account store lock unavailable".to_string(),
    })?;
    let mut store = load_account_store(&app)?;
    let Some(account) = store.accounts.iter_mut().find(|account| account.slot_id == slot_id) else {
        return Ok(()); // Removed already; nothing left to label.
    };
    account.display_name = name;
    account.avatar_url = avatar_url;
    save_account_store(&app, &store)
}

/// The webview data directory name for one account slot's own login partition.
///
/// The legacy slot keeps the exact original, unsuffixed name — see `LEGACY_ACCOUNT_SLOT_ID`.
/// Every other slot gets a directory nothing else uses, so two stored accounts can never share
/// (and therefore never cross-contaminate) a browser cookie jar.
fn login_partition_directory_name(slot_id: &str) -> String {
    if slot_id == LEGACY_ACCOUNT_SLOT_ID {
        YOUTUBE_LOGIN_DATA_DIR.to_string()
    } else {
        format!("{YOUTUBE_LOGIN_DATA_DIR}-{slot_id}")
    }
}

/// Builds the sign-in webview on one account slot's own storage partition.
///
/// Every slot — including a brand new candidate one about to attempt an interactive sign-in —
/// gets its own partition, never shared with any other slot. That is what makes "add another
/// account" foolproof without having to reverse-engineer Google's own multi-login cookie
/// behavior inside a webview profile: a fresh, empty partition can only ever show a
/// clean login/account-chooser screen, and a silent refresh against a specific slot's partition
/// can only ever renew *that* account's session, never a different stored one.
///
/// `loaded` is raised once a navigation finishes, which the silent refresh needs: cookies read
/// before the page has actually loaded are the same stale ones we already hold.
fn build_login_window(
    app: &tauri::AppHandle,
    visible: bool,
    loaded: Arc<AtomicBool>,
    slot_id: &str,
) -> Result<tauri::WebviewWindow, CommandError> {
    if let Some(existing) = app.get_webview_window(YOUTUBE_LOGIN_WINDOW) {
        let _ = existing.close();
    }

    let blank_url = "about:blank".parse().map_err(|error| CommandError {
        message: format!("invalid blank login URL: {error}"),
    })?;
    let window_builder = tauri::WebviewWindowBuilder::new(
        app,
        YOUTUBE_LOGIN_WINDOW,
        tauri::WebviewUrl::External(blank_url),
    )
    .title("Sign in to YouTube Music")
    .visible(visible)
    .skip_taskbar(!visible)
    .inner_size(520.0, 760.0)
    .on_page_load(move |_window, payload| {
        if payload.event() == tauri::webview::PageLoadEvent::Finished {
            loaded.store(true, Ordering::Relaxed);
        }
    });
    // See YOUTUBE_LOGIN_DATA_DIR: without its own partition, clearing this window's data
    // clears the main window's storage too.
    let window_builder = window_builder.data_directory(
        app.path()
            .app_local_data_dir()
            .map_err(|error| CommandError {
                message: format!("sign-in data directory unavailable: {error}"),
            })?
            .join(login_partition_directory_name(slot_id)),
    );

    window_builder.build().map_err(|error| CommandError {
        message: format!("unable to open YouTube Music sign-in: {error}"),
    })
}

/// Clears a stored account's own webview partition, e.g. when it is removed or when an
/// interactive sign-in's throwaway candidate partition went unused (it matched an
/// already-stored identity instead of becoming a new slot).
///
/// Goes through the webview's own `clear_all_browsing_data`, the same safe mechanism sign-out
/// has always used, rather than deleting files out from under a browser engine that might still
/// hold them open. The legacy partition is never touched here — it is shared with whichever
/// slot came from a pre-multi-account install, and clearing it out from under a *different*
/// stored account would be exactly the cross-contamination this design exists to prevent.
fn remove_login_partition(app: &tauri::AppHandle, slot_id: &str) {
    if slot_id == LEGACY_ACCOUNT_SLOT_ID {
        return;
    }
    let Ok(window) = build_login_window(app, false, Arc::new(AtomicBool::new(false)), slot_id) else {
        return;
    };
    let _ = window.clear_all_browsing_data();
    // The clear is asynchronous underneath and reports through a handler nobody waits on;
    // closing the webview out from under it can leave the partition half-cleared.
    thread::sleep(Duration::from_millis(750));
    let _ = window.close();
}

/// The session cookie as the login webview currently holds it, if it holds one at all.
fn harvest_session_cookie(
    window: &tauri::WebviewWindow,
) -> Result<Option<String>, CommandError> {
    let cookies = {
        let cookie_url: url::Url = "https://music.youtube.com/"
            .parse()
            .map_err(|error| CommandError {
                message: format!("invalid YouTube Music cookie URL: {error}"),
            })?;
        window
            .cookies_for_url(cookie_url)
            .map_err(|error| CommandError {
                message: format!("unable to read YouTube Music session: {error}"),
            })?
    };

    let cookie_names = cookies
        .iter()
        .map(|cookie| cookie.name())
        .collect::<std::collections::HashSet<_>>();
    let has_auth_cookie = ["SAPISID", "__Secure-1PAPISID", "__Secure-3PAPISID"]
        .iter()
        .any(|name| cookie_names.contains(name));
    let on_music_page = window
        .url()
        .map(|url| url.domain() == Some("music.youtube.com"))
        .unwrap_or(false);
    if !has_auth_cookie || !on_music_page {
        return Ok(None);
    }

    Ok(Some(
        cookies
            .iter()
            .map(|cookie| format!("{}={}", cookie.name(), cookie.value()))
            .collect::<Vec<_>>()
            .join("; "),
    ))
}

/// The outcome of an interactive sign-in.
///
/// `account_changed` is what stops a renewal from costing the user their library. Signing in
/// again is usually not a new account at all — it is the same person recovering a session that
/// lapsed, and wiping the cache and the chosen channel for that is a resync nobody asked for.
/// `slot_id` is the account's opaque handle for `switch_youtube_music_account` /
/// `remove_youtube_music_account` / `update_youtube_music_account_profile`.
#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct SignInResult {
    cookie: String,
    account_changed: bool,
    slot_id: String,
}

#[tauri::command]
async fn sign_in_youtube_music(
    app: tauri::AppHandle,
    jar: tauri::State<'_, YoutubeCookieJar>,
    account_lock: tauri::State<'_, AccountStoreLock>,
) -> Result<SignInResult, CommandError> {
    eprintln!("[internal][tauri][info] sign_in_youtube_music start");
    /*
     * A brand new candidate slot, up front — every interactive sign-in gets its own empty
     * webview partition (see `build_login_window`), so Google always shows a clean login or
     * account-chooser screen instead of silently continuing whatever identity a *shared*
     * partition last held. That ambiguity is exactly how adding a second account could
     * otherwise clobber the first one's session.
     *
     * If this sign-in turns out to re-authenticate an account already stored,
     * `upsert_signed_in_account` below finds it by identity and this candidate partition goes
     * unused — cleaned up rather than left as an orphaned directory.
     */
    let candidate_slot_id = generate_slot_id();
    let window = build_login_window(&app, true, Arc::new(AtomicBool::new(false)), &candidate_slot_id)?;
    eprintln!("[internal][tauri][info] sign_in_youtube_music login window created");

    let login_url = YOUTUBE_LOGIN_URL.parse().map_err(|error| CommandError {
        message: format!("invalid YouTube Music sign-in URL: {error}"),
    })?;
    window.navigate(login_url).map_err(|error| CommandError {
        message: format!("unable to navigate to YouTube Music sign-in: {error}"),
    })?;
    eprintln!("[internal][tauri][info] sign_in_youtube_music navigated to Google sign-in");

    for poll in 1..=300 {
        if let Some(cookie_header) = harvest_session_cookie(&window)? {
            let (slot_id, account_changed, reused_existing_slot) = {
                let _guard = account_lock.0.lock().map_err(|_| CommandError {
                    message: "account store lock unavailable".to_string(),
                })?;
                let mut store = load_account_store(&app)?;
                let (slot_id, account_changed) =
                    store.upsert_signed_in_account(&cookie_header, candidate_slot_id.clone());
                save_account_store(&app, &store)?;
                (slot_id.clone(), account_changed, slot_id != candidate_slot_id)
            };
            if reused_existing_slot {
                remove_login_partition(&app, &candidate_slot_id);
            }
            if let Ok(mut state) = jar.0.lock() {
                state.cookie = Some(cookie_header.clone());
                state.persisted_at = Some(Instant::now());
            }

            eprintln!(
                "[internal][tauri][info] sign_in_youtube_music detected session poll={} credential_bytes={} account_changed={} slot={}",
                poll,
                cookie_header.len(),
                account_changed,
                slot_id,
            );
            let _ = window.close();
            return Ok(SignInResult {
                cookie: cookie_header,
                account_changed,
                slot_id,
            });
        }

        if app.get_webview_window(YOUTUBE_LOGIN_WINDOW).is_none() {
            eprintln!(
                "[internal][tauri][warn] sign_in_youtube_music cancelled poll={}",
                poll
            );
            remove_login_partition(&app, &candidate_slot_id);
            return Err(CommandError {
                message: "YouTube Music sign-in was cancelled.".to_string(),
            });
        }
        thread::sleep(Duration::from_secs(1));
    }

    let _ = window.close();
    remove_login_partition(&app, &candidate_slot_id);
    eprintln!("[internal][tauri][warn] sign_in_youtube_music timed out");
    Err(CommandError {
        message: "YouTube Music sign-in timed out.".to_string(),
    })
}

/// Renews the session from the sign-in partition without involving the user.
///
/// Navigates to `YOUTUBE_LOGIN_URL` — the same Google entry point the interactive sign-in uses,
/// and the reason this works at all. Loading music.youtube.com directly does *not* re-mint
/// anything: presented with a retired `__Secure-*PSIDTS` it simply renders the signed-out page,
/// so this used to harvest the dead cookie back, report a renewal, and leave the app to discover
/// seconds later that it was still signed out. Only the accounts.google.com round trip reissues
/// the YouTube-domain cookies from the Google session the partition still holds.
///
/// The landing check in `harvest_session_cookie` does double duty here: reaching
/// music.youtube.com *is* the proof that Google accepted the session without asking anything.
/// When it needs a password or a second factor the redirect stops short, nothing is harvested,
/// and `None` says what it has always said — the sign-in genuinely lapsed and only the user can
/// fix it. Hidden throughout, because a window that needs interaction nobody can see is a window
/// that never finishes.
#[tauri::command]
async fn refresh_youtube_music_cookie(
    app: tauri::AppHandle,
    jar: tauri::State<'_, YoutubeCookieJar>,
    account_lock: tauri::State<'_, AccountStoreLock>,
) -> Result<Option<String>, CommandError> {
    eprintln!("[internal][tauri][info] refresh_youtube_music_cookie start");
    let active_slot_id = {
        let _guard = account_lock.0.lock().map_err(|_| CommandError {
            message: "account store lock unavailable".to_string(),
        })?;
        load_account_store(&app)?.active_slot_id
    };
    let Some(active_slot_id) = active_slot_id else {
        eprintln!("[internal][tauri][info] refresh_youtube_music_cookie no active account to renew");
        return Ok(None);
    };

    let loaded = Arc::new(AtomicBool::new(false));
    let window = build_login_window(&app, false, loaded.clone(), &active_slot_id)?;

    let login_url = YOUTUBE_LOGIN_URL.parse().map_err(|error| CommandError {
        message: format!("invalid YouTube Music sign-in URL: {error}"),
    })?;
    window.navigate(login_url).map_err(|error| CommandError {
        message: format!("unable to renew the YouTube Music session silently: {error}"),
    })?;

    for poll in 1..=YOUTUBE_SILENT_REFRESH_POLLS {
        // Only after a load: harvesting early returns the same stale cookie we came in with,
        // because nothing has been through a round trip to Google yet.
        if loaded.load(Ordering::Relaxed) {
            if let Some(cookie_header) = harvest_session_cookie(&window)? {
                eprintln!(
                    "[internal][tauri][info] refresh_youtube_music_cookie renewed poll={} credential_bytes={}",
                    poll,
                    cookie_header.len()
                );
                persist_active_account_cookie(&app, &account_lock, &jar, &active_slot_id, &cookie_header)?;
                let _ = window.close();
                return Ok(Some(cookie_header));
            }
        }
        thread::sleep(Duration::from_secs(1));
    }

    let _ = window.close();
    eprintln!("[internal][tauri][info] refresh_youtube_music_cookie found no usable session");
    Ok(None)
}

/// Signs out of whichever account is currently active — today's one-account "sign out".
///
/// With more than one account stored, another one automatically becomes active in its place
/// (the returned cookie is Some) rather than dropping to fully signed out, the same way removing
/// your active Google account from a browser falls back to another one still signed in there.
/// Signing out of the *last* account behaves exactly as it always has: fully signed out.
#[tauri::command]
async fn delete_youtube_music_cookie(
    app: tauri::AppHandle,
    jar: tauri::State<'_, YoutubeCookieJar>,
    account_lock: tauri::State<'_, AccountStoreLock>,
) -> Result<Option<String>, CommandError> {
    eprintln!("[internal][tauri][info] delete_youtube_music_cookie start");
    let active_slot_id = {
        let _guard = account_lock.0.lock().map_err(|_| CommandError {
            message: "account store lock unavailable".to_string(),
        })?;
        load_account_store(&app)?.active_slot_id
    };
    let Some(active_slot_id) = active_slot_id else {
        // Nothing was signed in at all; still clear the live jar for good measure.
        if let Ok(mut state) = jar.0.lock() {
            state.cookie = None;
            state.persisted_at = None;
        }
        eprintln!("[internal][tauri][info] delete_youtube_music_cookie nothing signed in");
        return Ok(None);
    };
    let new_active_cookie = remove_account_slot(&app, &account_lock, &jar, &active_slot_id)?;
    eprintln!(
        "[internal][tauri][info] delete_youtube_music_cookie complete fell_back={}",
        new_active_cookie.is_some()
    );
    Ok(new_active_cookie)
}

#[derive(Serialize)]
struct CommandError {
    message: String,
}

#[derive(serde::Deserialize)]
struct ProxyHttpRequestInput {
    url: String,
    method: String,
    headers: HashMap<String, String>,
    body_base64: Option<String>,
    timeout_ms: Option<u64>,
}

#[derive(Serialize)]
struct ProxyHttpResponse {
    status: u16,
    headers: HashMap<String, String>,
    body_base64: String,
    /// The rotated cookie, when this response changed it. Absent means "unchanged".
    #[serde(skip_serializing_if = "Option::is_none")]
    cookie: Option<String>,
}

/**
 * A media body, fetched in pieces wherever it is being read.
 *
 * Holds what has arrived as separate extents at their own offsets, the way a browser's media
 * cache does, so a resume at 18 minutes into a 35-minute mix needs the bytes *there* — which
 * the WebM cues, read from the head, point the demuxer straight at — and not everything before
 * them. A reader that reaches bytes not yet here says so (`wanted`) and waits;
 * `fetch_playback_pieces` fetches from that point first, and otherwise keeps a few minutes
 * ahead of `read_pos`.
 */
pub(crate) struct MediaBuffer {
    /// Arrived bytes by start offset. Never overlapping; adjacent extents are merged.
    extents: std::collections::BTreeMap<usize, Vec<u8>>,
    pub(crate) total: usize,
    /// Set when the download gave up: a reader waiting on it gets EOF instead of the timeout.
    pub(crate) failed: bool,
    /// Where a reader is waiting for bytes that are not here yet.
    pub(crate) wanted: Option<usize>,
    /// How far the reader has read, which read-ahead keeps ahead of.
    pub(crate) read_pos: usize,
    /// Wakes the fetcher when `wanted` or `read_pos` moves.
    pub(crate) wake: Arc<tokio::sync::Notify>,
}

impl MediaBuffer {
    fn pending(total: usize) -> Self {
        Self {
            extents: std::collections::BTreeMap::new(),
            total,
            failed: false,
            wanted: None,
            read_pos: 0,
            wake: Arc::new(tokio::sync::Notify::new()),
        }
    }

    /// Bytes servable from `pos` without a hole; `0` when `pos` itself has not arrived.
    pub(crate) fn available_from(&self, pos: usize) -> usize {
        match self.extents.range(..=pos).next_back() {
            Some((start, bytes)) if start + bytes.len() > pos => start + bytes.len() - pos,
            _ => 0,
        }
    }

    /// Whether every byte of the body has arrived.
    fn is_complete(&self) -> bool {
        self.total > 0 && self.available_from(0) >= self.total
    }

    /**
     * The first missing stretch at or after `from`, as `(start, end)` inclusive, cut at `limit`
     * and at the next extent so a fetch never asks for bytes already here. `None` when
     * everything from `from` to `limit` has arrived.
     */
    fn next_gap(&self, from: usize, limit: usize) -> Option<(usize, usize)> {
        let limit = limit.min(self.total.saturating_sub(1));
        let start = from + self.available_from(from);
        if start > limit || start >= self.total {
            return None;
        }
        let end = match self.extents.range(start..).next() {
            Some((next, _)) => (next - 1).min(limit),
            None => limit,
        };
        Some((start, end))
    }

    /// Replaces everything with one finished body, for the whole-file fallback.
    fn adopt_complete(&mut self, bytes: Vec<u8>) {
        self.total = bytes.len();
        self.extents = std::collections::BTreeMap::from([(0, bytes)]);
    }

    /**
     * Writes bytes that arrived at `offset`, extending the extent that ends there or starting
     * one, and joining the next extent once they meet. Bytes that would overlap one already
     * here are dropped: the fetcher only asks for gaps, so that is a server sending past the
     * range it was asked for.
     */
    fn write(&mut self, offset: usize, bytes: &[u8]) {
        // Whatever of these bytes is already here stays as it is
        let present = self.available_from(offset).min(bytes.len());
        let (offset, bytes) = (offset + present, &bytes[present..]);
        if bytes.is_empty() {
            return;
        }
        let next = self.extents.range(offset + 1..).next().map(|(start, _)| *start);
        let room = next.map_or(bytes.len(), |next| bytes.len().min(next.saturating_sub(offset)));
        let bytes = &bytes[..room.min(self.total.saturating_sub(offset))];
        if bytes.is_empty() {
            return;
        }
        let joined = match self.extents.range_mut(..=offset).next_back() {
            Some((start, extent)) if start + extent.len() == offset => {
                extent.extend_from_slice(bytes);
                *start
            }
            _ => {
                self.extents.insert(offset, bytes.to_vec());
                offset
            }
        };
        let end = joined + self.extents[&joined].len();
        if let Some(following) = self.extents.remove(&end) {
            self.extents.get_mut(&joined).expect("extent just written").extend(following);
        }
    }

    /// Copies `start..=end`, as far as it has arrived without a hole.
    pub(crate) fn read(&self, start: usize, end: usize) -> Vec<u8> {
        match self.extents.range(..=start).next_back() {
            Some((extent_start, bytes)) if extent_start + bytes.len() > start => {
                let from = start - extent_start;
                let to = (end + 1 - extent_start).min(bytes.len());
                bytes[from..to.max(from)].to_vec()
            }
            _ => Vec::new(),
        }
    }
}

fn collect_json_renderer_counts(value: &serde_json::Value, counts: &mut HashMap<String, usize>) {
    match value {
        serde_json::Value::Object(object) => {
            for (key, child) in object {
                if key.ends_with("Renderer")
                    || key.ends_with("Continuation")
                    || key.ends_with("Command")
                {
                    *counts.entry(key.clone()).or_default() += 1;
                }
                collect_json_renderer_counts(child, counts);
            }
        }
        serde_json::Value::Array(items) => {
            for item in items {
                collect_json_renderer_counts(item, counts);
            }
        }
        _ => {}
    }
}

/// Where downloaded audio lives. Separate from the metadata cache on purpose: that one is
/// JSON and size-capped for throwaway data, whereas these files are the user's explicit
/// "keep this" and must survive a cache clear.
fn offline_dir(app: &tauri::AppHandle) -> Result<PathBuf, CommandError> {
    app.path()
        .app_data_dir()
        .map(|path| path.join("offline-audio-v1"))
        .map_err(|error| cache_error(format!("offline directory unavailable: {error}")))
}

/// Track ids come from YouTube and are already filename-safe, but a hostile id must not be
/// able to escape the directory.
fn offline_entry_path(app: &tauri::AppHandle, track_id: &str) -> Result<PathBuf, CommandError> {
    let unsafe_char = track_id
        .chars()
        .any(|value| value == '/' || value == '\\' || value == ':' || value == '\0');
    if track_id.is_empty() || unsafe_char || track_id.contains("..") {
        return Err(cache_error("invalid offline track id"));
    }
    Ok(offline_dir(app)?.join(format!("{track_id}.bin")))
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct OfflineEntryInfo {
    track_id: String,
    byte_length: u64,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct OfflineStats {
    entry_count: u64,
    used_bytes: u64,
}

#[derive(Clone, Serialize)]
#[serde(rename_all = "camelCase")]
struct OfflineProgress {
    track_id: String,
    received_bytes: u64,
    total_bytes: u64,
    percent: u8,
}

/// Bytes per range request. Large enough that per-request overhead is negligible, small
/// enough that several are in flight at once on an ordinary connection.
const OFFLINE_CHUNK_BYTES: u64 = 4 * 1024 * 1024;

/// Range requests in flight at once.
///
/// googlevideo throttles a single sequential stream hard — that is the documented behaviour
/// media downloaders work around, and it is why downloading a track took far longer than
/// streaming the same track takes to buffer. Several ranges in parallel side-step it. Kept
/// modest so a download does not starve playback of the same connection.
const OFFLINE_CHUNK_CONCURRENCY: usize = 6;

/**
 * One playback request at a time, process-wide.
 *
 * Not a rate limit — a correctness guard. googlevideo answers 403 on the later of two range
 * requests that overlap on one session, so two tracks fetching at once means the one being
 * listened to loses its tail. Held for one piece (`AUDIO_PIECE_BYTES`), never for a whole
 * file: held for a whole file, a preloaded 38-minute mix kept the track just clicked waiting
 * 20 seconds for its first byte, and every such play fell back to the YouTube player.
 *
 * Downloads (`fetch_audio_ranged`) deliberately stay outside it: they fan out six ways on
 * purpose, they are a user-initiated bulk action rather than something a listener is waiting
 * on, and that path has not shown this failure.
 */
static PLAYBACK_REQUEST_LOCK: tokio::sync::Semaphore = tokio::sync::Semaphore::const_new(1);

/**
 * Readers waiting on bytes that have not arrived, across every playing and preloaded track.
 *
 * Read-ahead yields to them: it waits while one is waiting, and stops a piece it is part way
 * through, so a jump or a click waits at most for the request already on the wire.
 */
pub(crate) static PLAYBACK_READERS_WAITING: AtomicUsize = AtomicUsize::new(0);

/** Attempts per playback piece before falling back. A 403 here is usually transient. */
const PLAYBACK_RANGE_ATTEMPTS: usize = 3;
/** Delay before retrying a refused piece; doubled on each further attempt. */
const PLAYBACK_RETRY_BACKOFF: Duration = Duration::from_millis(250);

/// Bytes per playback request after the head: about a minute of ~150 kbps audio, a fraction of
/// a second to fetch.
const AUDIO_PIECE_BYTES: usize = 1024 * 1024;

/// How far past the reader playback is kept: about four minutes of ~150 kbps audio. A song is
/// all of it; a long mix is never pulled in whole.
const AUDIO_READ_AHEAD_BYTES: usize = 4 * 1024 * 1024;

/**
 * Smallest total worth splitting, and the floor on a range.
 *
 * Chunking a file below this buys nothing: the per-request overhead is a larger share than the
 * parallelism recovers.
 */
const AUDIO_MIN_CHUNK_BYTES: u64 = 512 * 1024;

/**
 * Range size for a given total.
 *
 * Aims for roughly `OFFLINE_CHUNK_CONCURRENCY` ranges so the whole file is in flight at once,
 * floored so a small file does not become a swarm of tiny requests and capped so a large one
 * does not become a handful of huge ones.
 *
 * A fixed 4 MiB was both the range size *and* the threshold, which meant a typical song — 2 to
 * 4 MB of Opus — fell under it and took the single sequential stream this exists to avoid.
 */
/**
 * Bytes in the first range.
 *
 * Deliberately much smaller than the rest. A media element cannot report `canplay` until it
 * has the container header and a little audio, and it asks for the whole file in one range —
 * so whatever the first chunk weighs is exactly how long a click waits for sound. Sizing it
 * like the others meant ~700 KB before the first note; this is enough to decode a header.
 */
const AUDIO_HEAD_CHUNK_BYTES: usize = 128 * 1024;

fn audio_chunk_size(total: u64) -> u64 {
    (total / OFFLINE_CHUNK_CONCURRENCY as u64)
        .max(AUDIO_MIN_CHUNK_BYTES)
        .min(OFFLINE_CHUNK_BYTES)
}

fn offline_http_client(request_url: &url::Url) -> Result<reqwest::Client, CommandError> {
    let mut client_builder = reqwest::Client::builder();
    if let Some(local_address) = signed_googlevideo_local_address(request_url) {
        client_builder = client_builder.local_address(local_address);
    }
    client_builder
        .build()
        .map_err(|error| cache_error(format!("audio HTTP client creation failed: {error}")))
}

/// Appends googlevideo's `range` query parameter.
///
/// The browser asks for bytes *here*, not with a Range header: a live YouTube Music session
/// sends `&range=1754030-3508710` and no Range header at all. A signed URL fetched with a Range
/// header is refused with a bare 403 and an empty body.
///
/// This is why every earlier attempt failed identically — two header styles, a bounded range and
/// an open one, four combinations, all refused. The Range header itself was the problem, so
/// varying its value or the headers around it could never have helped.
fn audio_url_with_range(url: &str, start: u64, end: u64) -> String {
    let separator = if url.contains('?') { '&' } else { '?' };
    format!("{url}{separator}range={start}-{end}")
}

/// Total byte length as declared by the URL's own `clen`.
///
/// Needed because a `range=` query answers 200 with just that slice rather than 206 with a
/// Content-Range, so the response cannot say how large the whole file is.
fn signed_content_length(request_url: &url::Url) -> Option<u64> {
    request_url
        .query_pairs()
        .find(|(key, _)| key == "clen")
        .and_then(|(_, value)| value.parse::<u64>().ok())
}

/// A googlevideo media request, dressed the way the browser dresses one.
///
/// Origin and Referer name music.youtube.com because that is the session the URL was issued to,
/// and the cookie because the player's own media requests are credentialed — googlevideo echoes
/// `access-control-allow-credentials` back at them.
fn googlevideo_audio_request(
    client: &reqwest::Client,
    url: &str,
    cookie: Option<&str>,
) -> reqwest::RequestBuilder {
    let request = client
        .get(url)
        .header("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36")
        .header("Accept", "*/*")
        // identity so the CDN does not gzip audio that is already compressed; the length
        // check downstream depends on Content-Length meaning what it says.
        .header("Accept-Encoding", "identity;q=1, *;q=0")
        .header("Accept-Language", "en-US,en;q=0.9")
        .header("Origin", "https://music.youtube.com")
        .header("Referer", "https://music.youtube.com/");

    match cookie.filter(|value| !value.trim().is_empty()) {
        Some(cookie) => request.header("Cookie", cookie),
        None => request,
    }
}

/// Fetches a signed audio URL whose byte range, if any, is already in the URL.
async fn send_audio_request(
    client: &reqwest::Client,
    url: &str,
    cookie: Option<&str>,
    track_id: &str,
) -> Result<reqwest::Response, CommandError> {
    let started_at = Instant::now();
    let response = googlevideo_audio_request(client, url, cookie)
        .send()
        .await
        .map_err(|error| cache_error(format!("audio request failed: {error}")))?;

    if response.status().is_success() {
        return Ok(response);
    }

    /*
     * googlevideo answers a refused media request with an empty body, so its reason — if it gives
     * one at all — is only ever in the response headers. None of them are secret.
     */
    let headers: Vec<String> = response
        .headers()
        .iter()
        .map(|(name, value)| format!("{name}={}", value.to_str().unwrap_or("?")))
        .collect();
    let status = response.status();
    eprintln!(
        "[internal][tauri][warn] googlevideo refused track_id={} status={} duration_ms={} headers=[{}]",
        track_id,
        status,
        started_at.elapsed().as_millis(),
        headers.join(", ")
    );

    Err(cache_error(format!("request returned {status}")))
}

fn emit_offline_progress(
    app: &tauri::AppHandle,
    track_id: &str,
    received: u64,
    total: u64,
    last_percent: &mut u8,
) {
    if total == 0 {
        return;
    }
    let percent = ((received * 100) / total).min(100) as u8;
    // One event per whole percent; a chunk-rate feed would flood the webview.
    if percent > *last_percent {
        *last_percent = percent;
        let _ = app.emit(
            "offline-download-progress",
            OfflineProgress {
                track_id: track_id.to_string(),
                received_bytes: received,
                total_bytes: total,
                percent,
            },
        );
    }
}

/// Downloads a track to the offline store, reporting real progress as it goes.
///
/// Tries parallel range requests first and falls back to a single stream when the server
/// answers 200 instead of 206 — a server that ignores Range would otherwise hand back the
/// whole body for every chunk and the pieces would be spliced into nonsense.
#[tauri::command]
async fn offline_audio_save(
    app: tauri::AppHandle,
    url: String,
    track_id: String,
    cookie: Option<String>,
) -> Result<u64, CommandError> {
    let request_url = url::Url::parse(&url)
        .map_err(|error| cache_error(format!("audio URL parse failed: {error}")))?;
    let started_at = Instant::now();

    /*
     * One line per download attempt, carrying the track it belongs to. The refusals used to be
     * correlatable only by their position in the file, which made a ladder of attempts across
     * several tracks genuinely hard to read.
     *
     * The URL is passed raw: the eprintln! macro sanitizes every line on its way out, so
     * pre-sanitizing here would redact the redaction and report the length of "[105ch]" rather
     * than of the signature.
     */
    eprintln!(
        "[internal][tauri][info] offline_audio_save request track_id={} url={}",
        track_id, url
    );

    let total_bytes = signed_content_length(&request_url).unwrap_or(0);
    let mut last_percent: u8 = 0;
    let bytes = fetch_audio_ranged(&url, &track_id, cookie.as_deref(), |received, total| {
        emit_offline_progress(&app, &track_id, received, total, &mut last_percent);
    })
    .await?;

    if bytes.is_empty() {
        return Err(cache_error("audio download returned no data"));
    }
    if total_bytes > 0 && (bytes.len() as u64) != total_bytes {
        return Err(cache_error(format!(
            "audio download was incomplete: {} of {} bytes",
            bytes.len(),
            total_bytes
        )));
    }

    write_offline_entry(&app, &track_id, &bytes, started_at, total_bytes > AUDIO_MIN_CHUNK_BYTES)
}

/**
 * Downloads a signed audio URL, in parallel ranges whenever the size is known.
 *
 * googlevideo throttles a single sequential stream hard, which is why one whole-file request
 * takes far longer than the same bytes fetched as several ranges at once. Shared by the
 * offline store and by native playback so the two cannot drift apart on speed — playback used
 * the slow path while the download feature used this one, and a skip paid for the difference.
 *
 * `on_progress` receives `(received, total)`. Playback passes a closure that does nothing.
 */
async fn fetch_audio_bytes(
    url: String,
    track_id: String,
    cookie: Option<String>,
) -> Result<Vec<u8>, CommandError> {
    let started_at = Instant::now();
    eprintln!(
        "[internal][tauri][info] fetch_audio_bytes start url={} track_id={}",
        url, track_id
    );
    let request_url = url::Url::parse(&url).map_err(|error| CommandError {
        message: format!("audio URL parse failed: {error}"),
    })?;
    let mut client_builder = reqwest::Client::builder();
    if let Some(local_address) = signed_googlevideo_local_address(&request_url) {
        eprintln!(
            "[internal][tauri][info] fetch_audio_bytes forcing signed IP family family={}",
            if local_address.is_ipv6() { "ipv6" } else { "ipv4" }
        );
        client_builder = client_builder.local_address(local_address);
    }
    let client = client_builder.build().map_err(|error| CommandError {
        message: format!("audio HTTP client creation failed: {error}"),
    })?;
    /*
     * The whole file in one request, asked for the way the browser asks: `range=0-{clen-1}` in
     * the query string. When `clen` is absent there is nothing to bound the request with, so it
     * goes out plain — still without a Range header, which is what gets these refused.
     */
    let ranged_url = match signed_content_length(&request_url) {
        Some(total) if total > 0 => audio_url_with_range(&url, 0, total - 1),
        _ => url.clone(),
    };
    let response = send_audio_request(&client, &ranged_url, cookie.as_deref(), &track_id).await?;

    let body = response.bytes().await.map_err(|error| {
        eprintln!(
            "[internal][tauri][error] fetch_audio_bytes body read failed url={} error={}",
            url, error
        );
        CommandError {
            message: format!("read body failed: {error}"),
        }
    })?;

    eprintln!(
        "[internal][tauri][info] fetch_audio_bytes success url={} bytes={} duration_ms={}",
        url,
        body.len(),
        started_at.elapsed().as_millis()
    );

    Ok(body.to_vec())
}

async fn fetch_audio_ranged(
    url: &str,
    track_id: &str,
    cookie: Option<&str>,
    mut on_progress: impl FnMut(u64, u64),
) -> Result<Vec<u8>, CommandError> {
    use futures_util::stream::StreamExt;

    let request_url = url::Url::parse(url)
        .map_err(|error| cache_error(format!("audio URL parse failed: {error}")))?;

    /*
     * `clen` rather than a probe request. A `range=` query is answered with 200 and just that
     * slice — there is no 206 and no Content-Range — so the response cannot report the total
     * size. The URL states the length itself, and it is covered by the signature, so it cannot
     * disagree with the file.
     */
    let total_bytes = signed_content_length(&request_url).unwrap_or(0);

    // Small enough for one request, or `clen` was absent and there is nothing to chunk by.
    if total_bytes <= AUDIO_MIN_CHUNK_BYTES {
        let whole = fetch_audio_bytes(
            url.to_string(),
            track_id.to_string(),
            cookie.map(str::to_string),
        )
        .await?;
        let received = whole.len() as u64;
        on_progress(received, if total_bytes > 0 { total_bytes } else { received });
        return Ok(whole);
    }

    let client = offline_http_client(&request_url)?;

    let chunk_size = audio_chunk_size(total_bytes);
    let mut ranges = Vec::new();
    let mut start = 0u64;
    while start < total_bytes {
        let end = (start + chunk_size - 1).min(total_bytes - 1);
        ranges.push((start, end));
        start = end + 1;
    }

    let mut chunks: Vec<(u64, Vec<u8>)> = Vec::with_capacity(ranges.len());
    let mut received = 0u64;
    let mut stream = futures_util::stream::iter(ranges.into_iter().map(|(start, end)| {
        let client = client.clone();
        let url = url.to_string();
        let cookie = cookie.map(str::to_string);
        async move {
            let response = googlevideo_audio_request(
                &client,
                &audio_url_with_range(&url, start, end),
                cookie.as_deref(),
            )
            .send()
            .await
            .map_err(|error| cache_error(format!("audio range request failed: {error}")))?;
            if !response.status().is_success() {
                return Err(cache_error(format!("range returned {}", response.status())));
            }
            let body = response
                .bytes()
                .await
                .map_err(|error| cache_error(format!("audio range read failed: {error}")))?;
            Ok::<(u64, Vec<u8>), CommandError>((start, body.to_vec()))
        }
    }))
    .buffer_unordered(OFFLINE_CHUNK_CONCURRENCY);

    let mut chunk_error: Option<CommandError> = None;
    while let Some(result) = stream.next().await {
        match result {
            Ok((start, body)) => {
                received += body.len() as u64;
                on_progress(received, total_bytes);
                chunks.push((start, body));
            }
            Err(error) => {
                chunk_error = Some(error);
                break;
            }
        }
    }
    drop(stream);

    // One refused chunk invalidates the whole assembly, so restart on the proven path instead
    // of returning a buffer with a hole in it.
    if let Some(error) = chunk_error {
        eprintln!(
            "[internal][tauri][warn] fetch_audio_ranged chunk failed ({}) falling back track_id={}",
            error.message, track_id
        );
        return fetch_audio_bytes(
            url.to_string(),
            track_id.to_string(),
            cookie.map(str::to_string),
        )
        .await;
    }

    // Ranges complete out of order, so the buffer is reassembled by offset.
    chunks.sort_by_key(|(start, _)| *start);
    let mut bytes = Vec::with_capacity(total_bytes as usize);
    for (_, body) in chunks {
        bytes.extend_from_slice(&body);
    }
    Ok(bytes)
}

/// Commits a completed download to the offline store.
///
/// Shared by the ranged and fallback paths so the temp-file-then-rename guarantee holds for
/// both: an interrupted write must never leave a truncated file that looks complete and then
/// fails to play.
fn write_offline_entry(
    app: &tauri::AppHandle,
    track_id: &str,
    bytes: &[u8],
    started_at: Instant,
    ranged: bool,
) -> Result<u64, CommandError> {
    let path = offline_entry_path(app, track_id)?;
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)
            .map_err(|error| cache_error(format!("offline directory creation failed: {error}")))?;
    }
    let temp_path = path.with_extension("part");
    fs::write(&temp_path, bytes)
        .map_err(|error| cache_error(format!("offline write failed: {error}")))?;
    fs::rename(&temp_path, &path)
        .map_err(|error| cache_error(format!("offline rename failed: {error}")))?;

    eprintln!(
        "[internal][tauri][info] offline_audio_save track_id={} bytes={} ranged={} duration_ms={}",
        track_id,
        bytes.len(),
        ranged,
        started_at.elapsed().as_millis()
    );
    Ok(bytes.len() as u64)
}

#[tauri::command]
fn offline_audio_remove(app: tauri::AppHandle, track_id: String) -> Result<(), CommandError> {
    let path = offline_entry_path(&app, &track_id)?;
    if path.exists() {
        fs::remove_file(&path)
            .map_err(|error| cache_error(format!("offline delete failed: {error}")))?;
    }
    Ok(())
}

/// The source of truth for what is downloaded. The frontend keeps its own manifest for track
/// metadata, but this is what reconciles it when the two disagree.
#[tauri::command]
fn offline_audio_list(app: tauri::AppHandle) -> Result<Vec<OfflineEntryInfo>, CommandError> {
    let dir = offline_dir(&app)?;
    if !dir.exists() {
        return Ok(Vec::new());
    }

    let mut entries = Vec::new();
    let read_dir = fs::read_dir(&dir)
        .map_err(|error| cache_error(format!("offline listing failed: {error}")))?;
    for entry in read_dir.flatten() {
        let path = entry.path();
        if path.extension().and_then(|value| value.to_str()) != Some("bin") {
            continue;
        }
        let Some(track_id) = path.file_stem().and_then(|value| value.to_str()) else {
            continue;
        };
        entries.push(OfflineEntryInfo {
            track_id: track_id.to_string(),
            byte_length: entry.metadata().map(|meta| meta.len()).unwrap_or(0),
        });
    }
    Ok(entries)
}

/// Deletes least-recently-*modified* entries until the store fits `max_bytes`.
///
/// Modification time rather than access time: access times are unreliable (often not kept) and
/// playing a track does not rewrite the file, so mtime is effectively "when it was
/// downloaded" -- a blunt but stable ordering.
#[tauri::command]
fn offline_audio_prune(app: tauri::AppHandle, max_bytes: u64) -> Result<OfflineStats, CommandError> {
    let dir = offline_dir(&app)?;
    if !dir.exists() {
        return Ok(OfflineStats {
            entry_count: 0,
            used_bytes: 0,
        });
    }

    let mut files: Vec<(PathBuf, u64, SystemTime)> = fs::read_dir(&dir)
        .map_err(|error| cache_error(format!("offline listing failed: {error}")))?
        .flatten()
        .filter_map(|entry| {
            let path = entry.path();
            if path.extension().and_then(|value| value.to_str()) != Some("bin") {
                return None;
            }
            let meta = entry.metadata().ok()?;
            Some((path, meta.len(), meta.modified().unwrap_or(UNIX_EPOCH)))
        })
        .collect();

    files.sort_by_key(|(_, _, modified)| *modified);
    let mut used_bytes: u64 = files.iter().map(|(_, size, _)| *size).sum();
    let mut entry_count = files.len() as u64;

    for (path, size, _) in &files {
        if used_bytes <= max_bytes {
            break;
        }
        if fs::remove_file(path).is_ok() {
            used_bytes = used_bytes.saturating_sub(*size);
            entry_count = entry_count.saturating_sub(1);
        }
    }

    Ok(OfflineStats {
        entry_count,
        used_bytes,
    })
}

/**
 * Rejects a body that is not the container that was asked for.
 *
 * Only meaningful for MP4: `resolveStreamUrl` falls back to Opus-in-WebM when a track has no
 * AAC, and "high" ranks across every format, so this has to follow what was requested rather
 * than assume.
 */
fn verify_audio_container(bytes: &[u8], mime_type: &str) -> Result<(), CommandError> {
    if !mime_type.contains("mp4") || bytes.len() < 12 || &bytes[4..8] == b"ftyp" {
        return Ok(());
    }
    let preview = String::from_utf8_lossy(&bytes[..bytes.len().min(120)]).replace('\n', " ");
    Err(CommandError {
        message: format!("Audio download was not an MP4 file. Response started with: {preview}"),
    })
}

/**
 * A short, log-safe look at bytes a decoder just rejected.
 *
 * `verify_audio_container` above only ever checks MP4 — a WebM/Opus response that is not
 * actually WebM sails through it untouched and is only ever caught once symphonia's probe
 * chokes on it, by which point the only trace left of *what* arrived is whatever this prints.
 * Both hex and a lossy UTF-8 decode: binary garbage reads as hex, but a wrong response is often
 * an HTML or JSON error page, which is unreadable as hex and exactly the case this exists for.
 */
fn bytes_preview(bytes: &[u8]) -> String {
    let head = &bytes[..bytes.len().min(32)];
    let hex: String = head.iter().map(|byte| format!("{byte:02x}")).collect();
    let text = String::from_utf8_lossy(&bytes[..bytes.len().min(120)]).replace('\n', " ");
    format!("{} bytes, starts hex={hex} text={text:?}", bytes.len())
}

/**
 * Fetches a playing or preloaded track in pieces, where it is being read.
 *
 * What comes next, in order: the head (header and the WebM cues the demuxer seeks with); the
 * bytes a reader is waiting on (a jump, a resume, playback catching up); then read-ahead,
 * `AUDIO_READ_AHEAD_BYTES` past where the reader is. Each piece goes into the buffer as it
 * arrives. One request at a time across the app (`PLAYBACK_REQUEST_LOCK`), and read-ahead
 * steps aside whenever another track's reader is waiting.
 *
 * Runs while a deck holds the track: `buffer` is weak, so once the reader and the deck's
 * health probe are gone — skipped, replaced, finished — the next look finds nothing and the
 * fetch stops. A failure marks the buffer so a waiting reader gets EOF instead of the timeout.
 */
async fn fetch_playback_pieces(
    url: String,
    track_id: String,
    cookie: Option<String>,
    mime_type: String,
    buffer: std::sync::Weak<Mutex<MediaBuffer>>,
    wake: Arc<tokio::sync::Notify>,
) {
    use futures_util::stream::StreamExt;

    let fail = |buffer: &std::sync::Weak<Mutex<MediaBuffer>>| {
        if let Some(buffer) = buffer.upgrade() {
            if let Ok(mut guard) = buffer.lock() {
                guard.failed = true;
            }
        }
    };

    let Ok(request_url) = url::Url::parse(&url) else {
        fail(&buffer);
        return;
    };
    let client = match offline_http_client(&request_url) {
        Ok(client) => client,
        Err(_) => {
            fail(&buffer);
            return;
        }
    };

    let mut head_verified = false;
    let mut failures = 0usize;
    let mut backoff = PLAYBACK_RETRY_BACKOFF;

    loop {
        /*
         * What to fetch next, decided under the lock and acted on outside it. `demand` is the
         * head or a reader of this track waiting; only read-ahead yields to other tracks.
         */
        let (job, own_waiting, head) = {
            let Some(strong) = buffer.upgrade() else { return };
            let Ok(guard) = strong.lock() else { return };
            if guard.failed {
                return;
            }
            if head_verified && guard.is_complete() {
                eprintln!(
                    "[internal][tauri][info] fetch_playback_pieces complete track_id={}",
                    track_id
                );
                return;
            }
            let own_waiting = guard.wanted.is_some();
            if !head_verified {
                match guard.next_gap(0, AUDIO_HEAD_CHUNK_BYTES - 1) {
                    Some(gap) => (Some((gap, true)), own_waiting, None),
                    // The head is here: checked before anything else is fetched
                    None => (None, own_waiting, Some(guard.read(0, AUDIO_HEAD_CHUNK_BYTES - 1))),
                }
            } else if let Some(gap) =
                guard.wanted.and_then(|at| guard.next_gap(at, at + AUDIO_PIECE_BYTES - 1))
            {
                (Some((gap, true)), own_waiting, None)
            } else {
                let from = guard.read_pos;
                let gap = guard
                    .next_gap(from, from + AUDIO_READ_AHEAD_BYTES - 1)
                    .map(|(start, end)| ((start, end.min(start + AUDIO_PIECE_BYTES - 1)), false));
                (gap, own_waiting, None)
            }
        };

        // The head is the only piece that can prove the container
        if let Some(head) = head {
            if let Err(error) = verify_audio_container(&head, &mime_type) {
                eprintln!(
                    "[internal][tauri][warn] fetch_playback_pieces bad container track_id={} error={}",
                    track_id, error.message
                );
                fail(&buffer);
                return;
            }
            head_verified = true;
            continue;
        }

        let Some(((start, end), demand)) = job else {
            // Nothing missing near the reader: wait for it to move on, or to jump
            let _ = tokio::time::timeout(Duration::from_millis(500), wake.notified()).await;
            continue;
        };

        let others_waiting =
            || PLAYBACK_READERS_WAITING.load(Ordering::SeqCst) > usize::from(own_waiting);
        if !demand && others_waiting() {
            let _ = tokio::time::timeout(Duration::from_millis(50), wake.notified()).await;
            continue;
        }
        let permit = PLAYBACK_REQUEST_LOCK.acquire().await;
        if !demand && others_waiting() {
            continue;
        }

        let started_at = Instant::now();
        let ranged = audio_url_with_range(&url, start as u64, end as u64);
        let mut received = 0usize;
        let mut preempted = false;
        let outcome: Result<(), String> =
            match googlevideo_audio_request(&client, &ranged, cookie.as_deref()).send().await {
                Ok(response) if response.status().is_success() => {
                    let mut pieces = response.bytes_stream();
                    let mut outcome = Ok(());
                    while let Some(piece) = pieces.next().await {
                        let bytes = match piece {
                            Ok(bytes) => bytes,
                            Err(error) => {
                                outcome = Err(format!(
                                    "audio piece read failed after {received} bytes: {error}"
                                ));
                                break;
                            }
                        };
                        let Some(strong) = buffer.upgrade() else { return };
                        match strong.lock() {
                            Ok(mut guard) if !guard.failed => guard.write(start + received, &bytes),
                            _ => return,
                        }
                        received += bytes.len();
                        // Another track's reader is waiting: the rest of this piece can wait
                        if !demand && others_waiting() {
                            preempted = true;
                            break;
                        }
                    }
                    if outcome.is_ok() && !preempted && start + received <= end {
                        outcome = Err(format!("audio piece ended short after {received} bytes"));
                    }
                    outcome
                }
                Ok(response) => Err(format!("piece returned {}", response.status())),
                Err(error) => Err(format!("audio piece request failed: {error}")),
            };
        drop(permit);

        match outcome {
            Ok(()) => {
                failures = 0;
                backoff = PLAYBACK_RETRY_BACKOFF;
                eprintln!(
                    "[internal][tauri][info] fetch_playback_pieces piece track_id={} start={} bytes={} ms={} demand={} preempted={}",
                    track_id,
                    start,
                    received,
                    started_at.elapsed().as_millis(),
                    demand,
                    preempted
                );
            }
            Err(message) => {
                failures += 1;
                eprintln!(
                    "[internal][tauri][warn] fetch_playback_pieces piece failed track_id={} start={} attempt={} error={}",
                    track_id, start, failures, message
                );
                if failures < PLAYBACK_RANGE_ATTEMPTS {
                    tokio::time::sleep(backoff).await;
                    backoff *= 2;
                    continue;
                }
                /*
                 * One refused piece is not a dead track. googlevideo refuses ranges often enough
                 * that playback has always fallen back to one whole-file request, which is
                 * slower but the path that has always worked. Not worth starting for a track no
                 * deck holds any more.
                 */
                if buffer.upgrade().is_none() {
                    return;
                }
                let _permit = PLAYBACK_REQUEST_LOCK.acquire().await;
                match fetch_audio_bytes(url.clone(), track_id.clone(), cookie.clone()).await {
                    Ok(whole)
                        if !whole.is_empty()
                            && verify_audio_container(&whole, &mime_type).is_ok() =>
                    {
                        if let Some(strong) = buffer.upgrade() {
                            if let Ok(mut guard) = strong.lock() {
                                guard.adopt_complete(whole);
                            }
                        }
                    }
                    _ => fail(&buffer),
                }
                return;
            }
        }
    }
}

/* ---------------------------------------------------------------------------------------- *
 * Native audio engine
 *
 * The `<audio>` path above hands bytes to the webview over loopback HTTP and lets Chromium
 * decode them. These commands hand the same bytes to symphonia instead, so nothing leaves the
 * Rust process — no media server round trip, no second copy of the song in the renderer, and
 * two real decks to fade between. `audio.rs` owns the decoding and output; this layer only
 * resolves a source into something readable and forwards the request.
 * ---------------------------------------------------------------------------------------- */

/**
 * Where a track's bytes come from. The three cases the player actually has.
 *
 * Each variant carries its **own** `rename_all`. The container attribute renames the *variants*
 * — which is what matches `kind: "stream"` — and does nothing at all to the fields inside them,
 * so with only the outer one this asked the frontend for `mime_type` and rejected every load
 * with "missing field `mime_type`". `rename_all_fields` would also work; this spells it out per
 * variant so a serde downgrade cannot quietly take it away again.
 */
#[derive(Deserialize)]
#[serde(rename_all = "camelCase", tag = "kind")]
enum NativeAudioSource {
    /// A signed googlevideo URL, decoded as it downloads.
    #[serde(rename_all = "camelCase")]
    Stream {
        url: String,
        mime_type: String,
        cookie: Option<String>,
    },
    /// A track already in the offline store.
    #[serde(rename_all = "camelCase")]
    Offline { track_id: String, mime_type: String },
    /// A file the user pointed at a music folder.
    #[serde(rename_all = "camelCase")]
    File { path: String },
}

/**
 * Opens a source as a blocking reader.
 *
 * The streaming case is the interesting one: it publishes an empty buffer sized from the URL's
 * own `clen`, starts fetching it in pieces (`fetch_playback_pieces`), and returns a reader over
 * it straight away. The decoder then reads the container header out of the head while the rest
 * is still arriving. The fetch holds the buffer weakly, so it runs exactly as long as the deck
 * that gets this reader holds the track.
 */
fn open_native_audio_reader(
    app: &tauri::AppHandle,
    track_id: &str,
    source: NativeAudioSource,
) -> Result<NativeAudioReader, CommandError> {
    match source {
        NativeAudioSource::Stream {
            url,
            mime_type,
            cookie,
        } => {
            let request_url = url::Url::parse(&url)
                .map_err(|error| cache_error(format!("audio URL parse failed: {error}")))?;
            let total = signed_content_length(&request_url).unwrap_or(0) as usize;
            if total == 0 {
                return Err(cache_error("audio URL declared no length"));
            }

            let buffer = Arc::new(Mutex::new(MediaBuffer::pending(total)));
            let wake = buffer
                .lock()
                .map(|guard| Arc::clone(&guard.wake))
                .map_err(|_| cache_error("audio buffer lock poisoned"))?;
            tauri::async_runtime::spawn(fetch_playback_pieces(
                url,
                track_id.to_string(),
                cookie,
                mime_type.clone(),
                Arc::downgrade(&buffer),
                wake,
            ));
            Ok(NativeAudioReader {
                reader: Box::new(audio::BufferReader::new(Arc::clone(&buffer))),
                mime_type,
                buffer: Some(buffer),
            })
        }
        NativeAudioSource::Offline { track_id, mime_type } => {
            let path = offline_entry_path(app, &track_id)?;
            let mut file = File::open(&path)
                .map_err(|error| cache_error(format!("offline read failed: {error}")))?;
            Ok(NativeAudioReader {
                mime_type: sniffed_mime(&mut file, mime_type, &track_id),
                reader: Box::new(file),
                buffer: None,
            })
        }
        NativeAudioSource::File { path } => {
            let path = PathBuf::from(path);
            // Re-validated here rather than trusted from the frontend, exactly as
            // `local_audio_read` does — this is the same trust boundary.
            if !path.is_file() || !is_local_audio_file(&path) {
                return Err(cache_error("local audio file is unavailable."));
            }
            // The extension is the only codec hint a local file carries, and it is a claim
            // rather than a fact — the bytes below get the final say.
            let declared = local_audio_mime_type(&path).to_string();
            let mut file = File::open(&path)
                .map_err(|error| cache_error(format!("local audio read failed: {error}")))?;
            let label = path.file_name().and_then(|name| name.to_str()).unwrap_or("file");
            Ok(NativeAudioReader {
                mime_type: sniffed_mime(&mut file, declared, label),
                reader: Box::new(file),
                buffer: None,
            })
        }
    }
}

/**
 * The container a stored body really is, preferring its own bytes over what was declared.
 *
 * Only for things already on disk. A *stream* keeps its declared type: that came from the format
 * selection which produced the very URL being fetched, so it cannot drift, and sniffing it would
 * mean waiting on the network before choosing a decoder.
 */
fn sniffed_mime(
    file: &mut File,
    declared: String,
    label: &str,
) -> String {
    match opus_source::sniff_container_mime(file) {
        Ok(Some(sniffed)) if sniffed != declared => {
            eprintln!(
                "[internal][tauri][info] container sniffed {} declared={} actual={}",
                label, declared, sniffed
            );
            sniffed.to_string()
        }
        Ok(_) => declared,
        // Unreadable here means unreadable for the decoder too; let that report it.
        Err(_) => declared,
    }
}

/**
 * A reader, plus the buffer behind it when one is still filling.
 *
 * The buffer comes back so a *failed* decode can abandon the download. Without it a track whose
 * codec symphonia cannot handle still pulled its whole body over the network — and, worse, took
 * turns on `PLAYBACK_REQUEST_LOCK` while doing it, so every refusal delayed the next real load.
 */
struct NativeAudioReader {
    /// `MediaSource` is `Read + Seek + Send + Sync` plus a length — exactly what symphonia's
    /// probe needs and a superset of what rodio's decoder does, so one box serves both.
    reader: Box<dyn symphonia::core::io::MediaSource>,
    /// The declared codec, which is what decides *which* decoder gets the box.
    mime_type: String,
    buffer: Option<Arc<Mutex<MediaBuffer>>>,
}



/**
 * Decodes a track onto a deck.
 *
 * `standby` loads it onto the idle deck instead of the playing one, which is what
 * `native_audio_transition` later swaps to. Returns the duration actually decoded, falling back
 * to the provider's when the container declares none — Opus in WebM usually does not.
 *
 * The decode runs on a blocking pool thread, not on the audio thread: building a decoder reads
 * the container header, and for a stream that means waiting on the network. Doing it here keeps
 * the audio thread free to go on reporting the position of the track that is still playing.
 */
#[tauri::command]
async fn native_audio_load(
    app: tauri::AppHandle,
    state: tauri::State<'_, audio::NativeAudio>,
    track_id: String,
    source: NativeAudioSource,
    duration_sec: Option<f64>,
    standby: Option<bool>,
) -> Result<f64, CommandError> {
    let NativeAudioReader { reader, mime_type, buffer } =
        open_native_audio_reader(&app, &track_id, source)?;
    let started_at = Instant::now();

    let decoded = tauri::async_runtime::spawn_blocking(move || {
        /*
         * Opus goes to libopus, everything else to rodio.
         *
         * Not a preference — symphonia has no Opus decoder at all, and rodio can only offer
         * what symphonia implements. WebM/Opus is the majority of what YouTube serves at
         * `high`, and the only audio offered for a large share of tracks, so this branch is
         * most of playback rather than an edge case.
         */
        if opus_source::is_opus(&mime_type) {
            return opus_source::OpusSource::new(reader, &mime_type).map(equalized);
        }
        rodio::Decoder::new(reader)
            .map(equalized)
            .map_err(|error| format!("audio decode failed: {error}"))
    })
    .await
    .map_err(|error| cache_error(format!("audio decode task failed: {error}")))?;

    /*
     * A decode that failed has no reader left, so the fill behind it is downloading a body
     * nobody will ever read. Marking the buffer stops it at its next piece and, more to the
     * point, ends its turns on the request lock — otherwise a run of undecodable tracks queues
     * a run of pointless downloads in front of the next one that would have played.
     */
    let (decoded, decoded_duration) = match decoded {
        Ok(decoded) => decoded,
        Err(message) => {
            // Read before `failed` is set — the preview is what actually arrived, and setting
            // the flag first would not change these bytes, only make the intent read backwards.
            let preview = buffer.as_ref().and_then(|buffer| {
                let guard = buffer.lock().ok()?;
                let available = guard.available_from(0);
                Some(bytes_preview(&guard.read(0, available.saturating_sub(1))))
            });
            if let Some(buffer) = &buffer {
                if let Ok(mut guard) = buffer.lock() {
                    guard.failed = true;
                }
            }
            eprintln!(
                "[internal][tauri][warn] native_audio_load decode failed track_id={} error={} preview=[{}]",
                track_id, message, preview.as_deref().unwrap_or("no stream buffer"),
            );
            return Err(cache_error(message));
        }
    };

    /*
     * The deck's window onto its own download.
     *
     * A deck is reported loaded as soon as the decoder can read the container header out of the
     * head chunk, while the rest of the file is still arriving. If that fill then fails — and
     * googlevideo refuses individual ranges often enough that it does — the deck still holds a
     * real source with a real duration, and nothing about it looks wrong until it is played and
     * stops after a few seconds. Handing the deck a probe is what lets `HasStandby` and
     * `Transition` refuse it instead of swapping into a track that cannot finish.
     *
     * Offline and local files pass `None`: their bytes are already on disk, so there is no
     * fill to fail.
     */
    let health: Option<audio::DeckHealth> = buffer.map(|buffer| {
        Arc::new(move || buffer.lock().map(|guard| !guard.failed).unwrap_or(false))
            as audio::DeckHealth
    });

    let duration = audio::request(&state, |reply| audio::Command::Load {
        track_id: track_id.clone(),
        source: decoded,
        fallback_duration_sec: duration_sec.unwrap_or(0.0),
        decoded_duration_sec: decoded_duration,
        standby: standby.unwrap_or(false),
        health,
        reply,
    })
    .map_err(cache_error)?
    .map_err(cache_error)?;

    eprintln!(
        "[internal][tauri][info] native_audio_load track_id={} standby={} duration_sec={} decode_ms={}",
        track_id,
        standby.unwrap_or(false),
        duration,
        started_at.elapsed().as_millis()
    );
    Ok(duration)
}

/**
 * Puts the equaliser and a limiter between a decoded stream and its deck.
 *
 * The limiter is not decoration. Ten bands boosted 12 dB is far more headroom than a normalised
 * track has, and without it the sum clips into distortion that sounds like a broken decoder
 * rather than like an equaliser set too high. rodio ships one, so this is a line.
 *
 * The duration is read *before* wrapping: it is what the caller reports back to the frontend,
 * and reading it through two adapters is one more place for it to go missing.
 */
fn equalized<S>(source: S) -> (audio::BoxedSource, Option<f64>)
where
    S: rodio::Source + Send + 'static,
{
    use rodio::Source as _;
    let duration = source.total_duration().map(|value| value.as_secs_f64());
    let shaped = equalizer::EqualizedSource::new(source).limit(rodio::source::LimitSettings::new());
    (Box::new(shaped) as audio::BoxedSource, duration)
}

/// The ten band gains and the preamp, in dB. Applies to whatever is playing, immediately.
#[tauri::command]
fn native_audio_set_equalizer(preamp_db: f32, bands_db: Vec<f32>) -> Result<(), CommandError> {
    if bands_db.len() != equalizer::BAND_COUNT {
        return Err(cache_error(format!(
            "equaliser expects {} bands, got {}",
            equalizer::BAND_COUNT,
            bands_db.len()
        )));
    }
    let mut values =
        equalizer::EqualizerValues { preamp_db, bands_db: [0.0; equalizer::BAND_COUNT] };
    values.bands_db.copy_from_slice(&bands_db);
    equalizer::set_values(values);
    Ok(())
}

#[tauri::command]
fn native_audio_play(state: tauri::State<'_, audio::NativeAudio>) -> Result<(), CommandError> {
    audio::request(&state, audio::Command::Play)
        .map_err(cache_error)?
        .map_err(cache_error)
}

#[tauri::command]
fn native_audio_pause(state: tauri::State<'_, audio::NativeAudio>) -> Result<(), CommandError> {
    state.send(audio::Command::Pause).map_err(cache_error)
}

#[tauri::command]
fn native_audio_stop(state: tauri::State<'_, audio::NativeAudio>) -> Result<(), CommandError> {
    state.send(audio::Command::Stop).map_err(cache_error)
}

#[tauri::command]
fn native_audio_seek(
    state: tauri::State<'_, audio::NativeAudio>,
    position_sec: f64,
) -> Result<(), CommandError> {
    state
        .send(audio::Command::Seek(position_sec))
        .map_err(cache_error)
}

#[tauri::command]
fn native_audio_set_volume(
    state: tauri::State<'_, audio::NativeAudio>,
    volume: f32,
    muted: bool,
) -> Result<(), CommandError> {
    state
        .send(audio::Command::Volume { volume, muted })
        .map_err(cache_error)
}

/**
 * Playback speed.
 *
 * ponytail: this resamples, so it transposes — a song at 1.25x plays a little sharp, where the
 * `<audio>` element corrected the pitch for free. Rate is a podcast feature in a music app and
 * defaults to 1, so it buys a time-stretcher's worth of DSP for very few listeners. Add
 * `signalsmith-stretch` between the decoder and the sink if it turns out to matter.
 */
#[tauri::command]
fn native_audio_set_rate(
    state: tauri::State<'_, audio::NativeAudio>,
    rate: f32,
) -> Result<(), CommandError> {
    state.send(audio::Command::Rate(rate)).map_err(cache_error)
}

/// Hands playback to the standby deck, over an equal-power crossfade when `fade_ms` is above
/// zero and in a single step when it is not. False means nothing was preloaded and the caller
/// should load normally.
#[tauri::command]
fn native_audio_transition(
    state: tauri::State<'_, audio::NativeAudio>,
    track_id: String,
    fade_ms: u64,
) -> Result<bool, CommandError> {
    audio::request(&state, |reply| audio::Command::Transition {
        track_id,
        fade_ms,
        reply,
    })
    .map_err(cache_error)
}

#[tauri::command]
fn native_audio_drop_standby(
    state: tauri::State<'_, audio::NativeAudio>,
) -> Result<(), CommandError> {
    state.send(audio::Command::DropStandby).map_err(cache_error)
}

/// Abandons the active deck's load without touching a standby that may already hold the next
/// track. See `Command::DropActive`.
#[tauri::command]
fn native_audio_drop_active(
    state: tauri::State<'_, audio::NativeAudio>,
) -> Result<(), CommandError> {
    state.send(audio::Command::DropActive).map_err(cache_error)
}

/// Devices cpal can currently see, for the output-device picker in Settings.
#[tauri::command]
fn native_audio_list_output_devices() -> Result<Vec<audio::AudioOutputDevice>, CommandError> {
    audio::list_output_devices().map_err(cache_error)
}

/// Switches the device the Rust engine plays to, by the `id` `native_audio_list_output_devices`
/// reported. `id: None` is the OS default. See `NativeAudio::set_output_device` for what this
/// does before playback has started versus during it — the latter clears both decks, so the
/// frontend reloads whatever was playing.
#[tauri::command]
fn native_audio_set_output_device(
    state: tauri::State<'_, audio::NativeAudio>,
    id: Option<String>,
) -> Result<(), CommandError> {
    state.set_output_device(id).map_err(cache_error)
}

#[tauri::command]
async fn proxy_http_request(
    app: tauri::AppHandle,
    jar: tauri::State<'_, YoutubeCookieJar>,
    account_lock: tauri::State<'_, AccountStoreLock>,
    mut input: ProxyHttpRequestInput,
) -> Result<ProxyHttpResponse, CommandError> {
    let started_at = Instant::now();
    let request_url = url::Url::parse(&input.url).map_err(|error| CommandError {
        message: format!("invalid URL: {error}"),
    })?;
    let request_target = format!(
        "{}://{}{}",
        request_url.scheme(),
        request_url.host_str().unwrap_or("unknown"),
        request_url.path()
    );
    eprintln!(
        "[internal][tauri][info] proxy_http_request start method={} url={} headers={} has_body={}",
        input.method,
        request_target,
        input.headers.len(),
        input.body_base64.is_some()
    );

    /*
     * Outgoing cookies come from the jar, not from the caller.
     *
     * youtubei.js bakes the cookie into a session when the client is constructed, so a session
     * that has been alive for hours would otherwise keep replaying whatever was current when it
     * was built. Only requests that already carry a Cookie header are stamped: the download
     * client is deliberately anonymous and has to stay that way.
     */
    let youtube_host = is_youtube_cookie_host(&request_url);
    if youtube_host {
        let live_cookie = jar
            .0
            .lock()
            .ok()
            .and_then(|state| state.cookie.clone());
        if let Some(live_cookie) = live_cookie {
            if let Some(key) = input
                .headers
                .keys()
                .find(|key| key.eq_ignore_ascii_case("cookie"))
                .cloned()
            {
                input.headers.insert(key, live_cookie);
            }
        }
    }

    /*
     * One line, not one call per header.
     *
     * This used to `eprintln!` every header separately — 10-15 calls per request, each through
     * the macro that sanitizes, writes to stderr *and* takes a mutex to append to the log file
     * on disk. A search-heavy session (or a track load, which alone fires several proxied
     * requests) turned this into hundreds of synchronous disk writes for a debug dump the line
     * above it already summarizes the count of. Joining first pays that cost once per request
     * instead of once per header, with the same redaction.
     */
    if !input.headers.is_empty() {
        let header_summary = input
            .headers
            .iter()
            .map(|(key, value)| {
                let normalized_key = key.to_ascii_lowercase();
                let safe_value = if normalized_key == "authorization" || normalized_key == "cookie"
                {
                    "[redacted]"
                } else {
                    value.as_str()
                };
                format!("{key}={safe_value}")
            })
            .collect::<Vec<_>>()
            .join(", ");
        eprintln!("[internal][tauri][debug] proxy_http_request headers: {header_summary}");
    }
    let method = reqwest::Method::from_bytes(input.method.as_bytes()).map_err(|error| {
        eprintln!(
            "[internal][tauri][error] proxy_http_request invalid method={} error={}",
            input.method, error
        );
        CommandError {
            message: format!("invalid method: {error}"),
        }
    })?;

    let mut client_builder = reqwest::Client::builder()
        .user_agent("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/135.0.0.0 Safari/537.36");

    if let Some(timeout_ms) = input.timeout_ms {
        client_builder = client_builder.timeout(Duration::from_millis(timeout_ms));
    }

    if let Some(local_address) = signed_googlevideo_local_address(&request_url) {
        eprintln!(
            "[internal][tauri][info] proxy_http_request forcing signed IP family url={} family={}",
            request_target,
            if local_address.is_ipv6() { "ipv6" } else { "ipv4" }
        );
        client_builder = client_builder.local_address(local_address);
    }

    let client = client_builder.build().map_err(|error| CommandError {
        message: format!("HTTP client creation failed: {error}"),
    })?;
    let mut request = client.request(method, &input.url);

    for (key, value) in &input.headers {
        request = request.header(key, value);
    }

    if let Some(body_base64) = input.body_base64 {
        let bytes = STANDARD.decode(body_base64).map_err(|error| {
            eprintln!(
                "[internal][tauri][error] proxy_http_request body decode failed url={} error={}",
                input.url, error
            );
            CommandError {
                message: format!("invalid body encoding: {error}"),
            }
        })?;
        request = request.body(bytes);
    }

    let response = request.send().await.map_err(|error| {
        // reqwest's own Display is just the top-level "error sending request for url" wrapper —
        // the actual cause (DNS failure, TLS handshake, connection refused/reset) lives in the
        // source chain underneath it and was getting dropped, leaving every network failure
        // indistinguishable in the log from every other one.
        eprintln!(
            "[internal][tauri][error] proxy_http_request request failed url={} error={}",
            input.url,
            error_cause_chain(&error)
        );
        CommandError {
            message: format!("request failed: {}", error_cause_chain(&error)),
        }
    })?;

    let status = response.status().as_u16();
    let mut headers = HashMap::new();
    for (key, value) in response.headers() {
        if let Ok(value_str) = value.to_str() {
            headers.insert(key.to_string(), value_str.to_string());
        }
    }

    // Read before the map above flattens them: a response sets several cookies at once, and a
    // HashMap keeps only the last.
    let refreshed_cookie = if youtube_host {
        let set_cookies = response
            .headers()
            .get_all(reqwest::header::SET_COOKIE)
            .iter()
            .filter_map(|value| value.to_str().ok().map(str::to_string))
            .collect::<Vec<_>>();
        (!set_cookies.is_empty())
            .then(|| refresh_youtube_cookie_jar(&app, &jar, &account_lock, &set_cookies))
            .flatten()
    } else {
        None
    };

    let body = response.bytes().await.map_err(|error| {
        eprintln!(
            "[internal][tauri][error] proxy_http_request body read failed url={} error={}",
            input.url, error
        );
        CommandError {
            message: format!("read body failed: {error}"),
        }
    })?;

    if request_url.path().ends_with("/browse") && status < 400 {
        if let Ok(json) = serde_json::from_slice::<serde_json::Value>(&body) {
            let top_level_keys = json
                .as_object()
                .map(|object| object.keys().cloned().collect::<Vec<_>>())
                .unwrap_or_default();
            let mut renderer_counts = HashMap::new();
            collect_json_renderer_counts(&json, &mut renderer_counts);
            eprintln!(
                "[internal][tauri][debug] proxy_http_request browse_shape top_level_keys={:?} renderer_counts={:?}",
                top_level_keys, renderer_counts
            );
        }
    }

    if status >= 400 {
        eprintln!(
            "[internal][tauri][warn] proxy_http_request error_response method={} url={} status={} bytes={}",
            input.method,
            request_target,
            status,
            body.len()
        );
    }

    eprintln!(
        "[internal][tauri][info] proxy_http_request success method={} url={} status={} bytes={} duration_ms={}",
        input.method,
        request_target,
        status,
        body.len(),
        started_at.elapsed().as_millis()
    );

    Ok(ProxyHttpResponse {
        status,
        headers,
        body_base64: STANDARD.encode(body),
        cookie: refreshed_cookie,
    })
}

#[tauri::command]
fn discord_rpc_update(
    discord_manager: tauri::State<
        '_,
        std::sync::Arc<std::sync::Mutex<discord_rpc::DiscordRpcManager>>,
    >,
    title: String,
    artist: String,
    album: String,
    artwork_url: Option<String>,
    song_url: Option<String>,
    artist_url: Option<String>,
    album_url: Option<String>,
    duration: u64,
    current_time: u64,
    is_playing: bool,
) -> Result<(), CommandError> {
    let data = discord_rpc::DiscordPresenceData {
        title,
        artist,
        album,
        artwork_url,
        song_url,
        artist_url,
        album_url,
        duration,
        current_time,
        is_playing,
    };

    match discord_manager.lock() {
        Ok(manager) => {
            if let Err(e) = manager.update_presence(data) {
                eprintln!("[internal][discord_rpc] failed to update presence: {}", e);
                // Don't return error - Discord might not be running
            }
        }
        Err(e) => {
            eprintln!("[internal][discord_rpc] failed to lock manager: {}", e);
        }
    }
    Ok(())
}

#[tauri::command]
fn discord_rpc_clear(
    discord_manager: tauri::State<
        '_,
        std::sync::Arc<std::sync::Mutex<discord_rpc::DiscordRpcManager>>,
    >,
) -> Result<(), CommandError> {
    match discord_manager.lock() {
        Ok(manager) => {
            if let Err(e) = manager.clear_presence() {
                eprintln!("[internal][discord_rpc] failed to clear presence: {}", e);
            }
        }
        Err(e) => {
            eprintln!("[internal][discord_rpc] failed to lock manager: {}", e);
        }
    }
    Ok(())
}

/**
 * The port the release build serves its interface on, the same on every launch.
 *
 * The page's origin is `http://localhost:<port>`, and WebKit keeps local storage per origin: a
 * port picked at random on each launch gave every launch a new, empty store. What the app saved
 * there (the session, play history, its own settings) never came back, and each launch left its
 * database behind — hundreds of MB after a few weeks. If something else holds this port, the
 * launch falls back to a random one, and to an empty store, rather than not starting.
 */
#[cfg(not(debug_assertions))]
const LOCAL_PORT: u16 = 47821;

#[cfg(not(debug_assertions))]
fn local_port() -> u16 {
    if portpicker::is_free(LOCAL_PORT) {
        return LOCAL_PORT;
    }
    eprintln!("[internal][tauri][warn] localhost port {LOCAL_PORT} is in use, using a random one");
    pick_unused_port().expect("failed to find an unused localhost port")
}

/**
 * Moves the newest store of the random-port launches to `LOCAL_PORT`'s origin, once, before
 * WebKit opens it: what the last launch saved carries over to the fixed origin. The older stores
 * are left as they are.
 *
 * WebKit keeps an origin's local storage in `<app data>/localstorage/<scheme>_<host>_<port>
 * .localstorage`, an SQLite database with `-wal` and `-shm` beside it; the newest data can be in
 * the `-wal`, so the three move together and age is the newest of their times.
 */
#[cfg(not(debug_assertions))]
fn adopt_newest_local_storage(identifier: &str) {
    let Some(data_home) = std::env::var_os("XDG_DATA_HOME")
        .map(PathBuf::from)
        .or_else(|| std::env::var_os("HOME").map(|home| PathBuf::from(home).join(".local/share")))
    else {
        return;
    };
    let dir = data_home.join(identifier).join("localstorage");
    let target = dir.join(format!("http_localhost_{LOCAL_PORT}.localstorage"));
    if target.exists() {
        return;
    }
    let Ok(entries) = fs::read_dir(&dir) else { return };

    let modified = |path: &Path| fs::metadata(path).and_then(|meta| meta.modified()).ok();
    let newest = entries
        .filter_map(|entry| entry.ok().map(|entry| entry.path()))
        .filter(|path| {
            path.file_name()
                .and_then(|name| name.to_str())
                .and_then(|name| name.strip_prefix("http_localhost_"))
                .and_then(|rest| rest.strip_suffix(".localstorage"))
                .is_some_and(|port| !port.is_empty() && port.bytes().all(|b| b.is_ascii_digit()))
        })
        .filter_map(|path| {
            let wal = PathBuf::from(format!("{}-wal", path.display()));
            let time = modified(&path).max(modified(&wal))?;
            Some((time, path))
        })
        .max_by_key(|(time, _)| *time);
    let Some((_, source)) = newest else { return };

    for suffix in ["", "-wal", "-shm"] {
        let from = PathBuf::from(format!("{}{suffix}", source.display()));
        let to = PathBuf::from(format!("{}{suffix}", target.display()));
        if from.exists() {
            if let Err(error) = fs::rename(&from, &to) {
                eprintln!(
                    "[internal][tauri][warn] failed to move local storage from={} error={error}",
                    from.display()
                );
                return;
            }
        }
    }
    eprintln!(
        "[internal][tauri][info] local storage moved to the fixed origin from={}",
        source.display()
    );
}

pub fn run() {
    // Initialize Discord RPC manager
    let discord_manager =
        std::sync::Arc::new(std::sync::Mutex::new(discord_rpc::DiscordRpcManager::new()));

    #[allow(unused_mut)]
    let mut context = tauri::generate_context!();
    #[allow(unused_mut)]
    let mut builder = tauri::Builder::default()
        /*
         * First among plugins, per the plugin's own docs — it is the one deciding whether this
         * process gets to keep running at all, so everything else registering a window or a
         * background task first would be work thrown away the instant a second launch
         * turns out to be redundant.
         *
         * The callback runs in the *original* process when a second launch is attempted; a
         * second launch's own `main` never reaches this builder at all, since the plugin exits
         * it immediately. It brings the window to the front — a second launch is exactly that,
         * wherever it came from.
         */
        .plugin(tauri_plugin_single_instance::init(|app, _argv, _cwd| {
            show_main_window(app);
        }))
        .manage(CacheLock(Mutex::new(())))
        .manage(AppSettingsLock(Mutex::new(())))
        .manage(AccountStoreLock(Mutex::new(())))
        .manage(YoutubeCookieJar(Mutex::new(CookieJarState::default())))
        .manage(discord_manager)
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_opener::init());

    #[cfg(not(debug_assertions))]
    {
        let port = local_port();
        if port == LOCAL_PORT {
            adopt_newest_local_storage(&context.config().identifier);
        }
        let url: url::Url = format!("http://localhost:{}", port)
            .parse()
            .expect("failed to parse localhost url");
        let _window_url = WindowUrl::External(url.clone());

        context.config_mut().build.frontend_dist = Some(FrontendDist::Url(url));
        builder = builder.plugin(tauri_plugin_localhost::Builder::new(port).build());
    }

    let builder = builder.manage(linux_media::LinuxMediaSession::new());

    builder
        .manage(LocalAudioWatcher(Mutex::new(None)))
        .setup(|app| {
            /*
             * The audio thread and its output device are not opened here — `NativeAudio` starts
             * them on the first command. A listener on the IFrame engine should never claim a
             * handle from the OS mixer for a decoder they will not use.
             */
            app.manage(audio::NativeAudio::new(app.handle().clone()));
            if let Err(error) = initialize_app_log(app.handle()) {
                std::eprintln!("[internal][tauri][warn] {}", error.message);
            }
            Ok(())
        })
        .on_window_event(move |window, event| match event {
            tauri::WindowEvent::CloseRequested { api, .. } => {
                eprintln!(
                    "[internal][tauri][info] window close requested label={}",
                    window.label()
                );
                if window.label() == "main" {
                    api.prevent_close();
                    window.app_handle().exit(0);
                }
            }
            _ => {}
        })
        .invoke_handler(tauri::generate_handler![
            frontend_log,
            app_setting_get,
            app_setting_set,
            app_setting_remove,
            app_settings_clear,
            open_current_log,
            offline_audio_save,
            offline_audio_remove,
            offline_audio_list,
            offline_audio_prune,
            native_audio_load,
            native_audio_play,
            native_audio_pause,
            native_audio_stop,
            native_audio_seek,
            native_audio_set_volume,
            native_audio_set_rate,
            native_audio_transition,
            native_audio_drop_standby,
            native_audio_drop_active,
            native_audio_set_equalizer,
            native_audio_list_output_devices,
            native_audio_set_output_device,
            proxy_http_request,
            load_youtube_music_cookie,
            sign_in_youtube_music,
            refresh_youtube_music_cookie,
            delete_youtube_music_cookie,
            list_youtube_music_accounts,
            switch_youtube_music_account,
            remove_youtube_music_account,
            update_youtube_music_account_profile,
            cache_get,
            cache_set,
            cache_stats,
            cache_set_max_bytes,
            cache_clear,
            local_audio_scan,
            read_text_file,
            write_text_file,
            local_audio_read_tags,
            local_audio_artwork,
            read_image_file,
            local_audio_write_tags,
            local_audio_watch,
            lastfm::lastfm_auth_token,
            lastfm::lastfm_complete_auth,
            lastfm::lastfm_disconnect,
            lastfm::lastfm_get_session,
            lastfm::lastfm_scrobble,
            lastfm::lastfm_update_now_playing,
            discord_rpc_update,
            discord_rpc_clear,
            linux_media::update_linux_media_session
        ])
        .run(context)
        .expect("error while running tauri application");
}

#[cfg(test)]
mod tests {
    use super::{
        apply_set_cookie, audio_url_with_range, cookie_account_identity,
        error_cause_chain, is_slow_persist_cookie, is_youtube_cookie_host, parse_cookie_header, sanitize_log_url,
        audio_chunk_size, serialize_cookie_pairs, MediaBuffer, signed_content_length, AUDIO_MIN_CHUNK_BYTES, OFFLINE_CHUNK_BYTES,
        PLAYBACK_READERS_WAITING, bytes_preview,
        YoutubeAccountStore, generate_slot_id, login_partition_directory_name,
        LEGACY_ACCOUNT_SLOT_ID,
    };
    use std::sync::atomic::Ordering;
    use super::audio::BufferReader;
    use super::NativeAudioSource;
    use std::io::{Read, Seek, SeekFrom};
    use std::sync::{Arc, Mutex};
    use std::time::Duration;

    /**
     * Which decoder a track is sent to.
     *
     * The consequence of getting this wrong is not a fallback, it is a failed load: rodio
     * cannot decode Opus at all, and libopus cannot read anything else. The `audio/mp4` case is
     * the one that already worked when every WebM track was failing, so it is the one that must
     * not start being routed to libopus.
     */
    #[test]
    fn opus_routing_follows_the_declared_codec() {
        use super::opus_source::is_opus;

        // What YouTube actually serves at `high` — 13 of 14 resolves in the log that found this.
        assert!(is_opus(r#"audio/webm; codecs="opus""#));
        assert!(is_opus("audio/opus"), "a local .opus file");
        assert!(is_opus("audio/webm"), "WebM carries no other audio codec worth guessing");
        assert!(is_opus("AUDIO/WEBM; CODECS=\"OPUS\""), "the header case is not ours to assume");

        assert!(!is_opus(r#"audio/mp4; codecs="mp4a.40.2""#), "AAC is rodio's");
        assert!(!is_opus("audio/flac"));
        assert!(!is_opus("audio/mpeg"));
        // Ogg is Vorbis far more often than Opus, and rodio has a Vorbis decoder. An Opus
        // stream in an `.ogg` wrapper is the one shape this deliberately misroutes.
        assert!(!is_opus("audio/ogg"));
    }

    /**
     * The exact JSON `rustAudio.ts` puts on the wire.
     *
     * A cross-language boundary that neither `tsc` nor `cargo` can see across: TypeScript sends
     * `mimeType`, and `#[serde(rename_all)]` on an *enum* renames its variants and not their
     * fields, so every load was rejected with "missing field `mime_type`" while both sides
     * compiled and every other check passed. The payloads below are copied from the invoke
     * calls; keep them that way.
     */
    #[test]
    fn native_audio_source_parses_what_the_frontend_sends() {
        let stream = serde_json::from_str::<NativeAudioSource>(
            r#"{"kind":"stream","url":"https://r1.googlevideo.com/videoplayback?clen=99","mimeType":"audio/webm; codecs=\"opus\"","cookie":"SAPISID=x"}"#,
        )
        .expect("stream source");
        match stream {
            NativeAudioSource::Stream { url, mime_type, cookie } => {
                assert!(url.contains("googlevideo"));
                assert_eq!(mime_type, "audio/webm; codecs=\"opus\"");
                assert_eq!(cookie.as_deref(), Some("SAPISID=x"));
            }
            _ => panic!("kind did not select the stream variant"),
        }

        // The cookie is absent when the session is signed out, and absent must not mean invalid.
        let anonymous = serde_json::from_str::<NativeAudioSource>(
            r#"{"kind":"stream","url":"https://r1.googlevideo.com/videoplayback","mimeType":"audio/mp4"}"#,
        );
        assert!(anonymous.is_ok(), "a missing cookie is a signed-out session, not an error");

        let offline = serde_json::from_str::<NativeAudioSource>(
            r#"{"kind":"offline","trackId":"dQw4w9WgXcQ","mimeType":"audio/webm; codecs=\"opus\""}"#,
        )
        .expect("offline source");
        // The mime type rides along because a downloaded body has no extension to read it from,
        // and it is what decides whether libopus or rodio gets the file.
        match offline {
            NativeAudioSource::Offline { track_id, mime_type } => {
                assert_eq!(track_id, "dQw4w9WgXcQ");
                assert!(super::opus_source::is_opus(&mime_type));
            }
            _ => panic!("kind did not select the offline variant"),
        }

        let file = serde_json::from_str::<NativeAudioSource>(
            r#"{"kind":"file","path":"C:\\Music\\song.flac"}"#,
        )
        .expect("file source");
        assert!(matches!(file, NativeAudioSource::File { path } if path.ends_with("song.flac")));

        // snake_case is what the bug accepted; it must not be what the contract accepts.
        assert!(
            serde_json::from_str::<NativeAudioSource>(
                r#"{"kind":"stream","url":"https://x/y","mime_type":"audio/mp4"}"#,
            )
            .is_err(),
            "the wire format is camelCase and only camelCase",
        );
    }

    /**
     * The streaming reader the Rust decoder pulls through.
     *
     * Bytes arrive wherever they are being read, so a reader must only ever hand the decoder
     * bytes from where it is — never the next extent that happens to be here — and a read at a
     * hole must say where it waits and wait, not answer short: 0 would look like the end of the
     * track.
     */
    #[test]
    fn buffer_reader_waits_where_it_reads_and_says_so() {
        let buffer = Arc::new(Mutex::new(MediaBuffer::pending(8)));
        let mut reader = BufferReader::new(Arc::clone(&buffer));

        buffer.lock().unwrap().write(0, &[1, 2]);
        let mut out = [0u8; 8];
        let read = reader.read(&mut out).unwrap();
        assert_eq!(&out[..read], &[1, 2]);
        assert_eq!(buffer.lock().unwrap().read_pos, 2, "read-ahead follows the reader");

        // A jump past what has arrived: the reader waits there, and says so
        reader.seek(SeekFrom::Start(5)).unwrap();
        let filling = Arc::clone(&buffer);
        let filler = std::thread::spawn(move || {
            std::thread::sleep(Duration::from_millis(30));
            let wanted = filling.lock().unwrap().wanted;
            let waiting = PLAYBACK_READERS_WAITING.load(Ordering::SeqCst);
            filling.lock().unwrap().write(5, &[6, 7, 8]);
            (wanted, waiting)
        });
        let started_at = std::time::Instant::now();
        let read = reader.read(&mut out).unwrap();
        assert_eq!(&out[..read], &[6, 7, 8], "the bytes at the jump, not the head");
        assert!(started_at.elapsed() >= Duration::from_millis(25));
        let (wanted, waiting) = filler.join().unwrap();
        assert_eq!(wanted, Some(5), "the fetcher is told where the reader waits");
        assert!(waiting >= 1, "other tracks' read-ahead is told a reader waits");
        assert_eq!(buffer.lock().unwrap().wanted, None, "taken back once the bytes are here");

        /*
         * The hole at 2 never fills and the download gives up. EOF, not an error and not a
         * hang: the decoder finishes the frames it has and the track reports its end, so the
         * queue advances instead of stalling on a deck that will never empty.
         */
        reader.seek(SeekFrom::Start(2)).unwrap();
        buffer.lock().unwrap().failed = true;
        assert_eq!(reader.read(&mut out).unwrap(), 0);

        // Symphonia probes containers by seeking around; past the end must clamp rather than
        // fail, or a probe of a body still downloading kills the load.
        assert_eq!(reader.seek(SeekFrom::End(0)).unwrap(), 8);
        assert_eq!(reader.seek(SeekFrom::Start(999)).unwrap(), 8);
        assert_eq!(reader.seek(SeekFrom::Start(2)).unwrap(), 2);
    }

    /// Pieces land anywhere, and the buffer tells the fetcher exactly which bytes are still
    /// missing — a gap asked for twice is a wasted request, and one never asked for is a hole.
    #[test]
    fn media_buffer_holds_pieces_anywhere_and_finds_the_gaps() {
        let mut buffer = MediaBuffer::pending(10);
        assert_eq!(buffer.next_gap(0, 9), Some((0, 9)));

        // A resume: bytes far in arrive before the start
        buffer.write(6, &[7, 8]);
        assert_eq!(buffer.available_from(0), 0);
        assert_eq!(buffer.available_from(6), 2);
        assert_eq!(buffer.available_from(7), 1);
        assert_eq!(buffer.read(6, 7), vec![7, 8]);
        assert_eq!(buffer.next_gap(0, 9), Some((0, 5)), "stops at what is already here");

        buffer.write(0, &[1, 2, 3]);
        assert_eq!(buffer.next_gap(0, 9), Some((3, 5)));
        assert_eq!(buffer.next_gap(6, 9), Some((8, 9)), "skips what is here");
        assert_eq!(buffer.next_gap(6, 7), None, "nothing missing up to the limit");

        // The hole closes: the extents join and read as one run
        buffer.write(3, &[4, 5, 6]);
        assert_eq!(buffer.available_from(0), 8);
        assert_eq!(buffer.read(2, 7), vec![3, 4, 5, 6, 7, 8]);

        // A server sending past the end is cut at the end
        buffer.write(8, &[9, 10, 11]);
        assert!(buffer.is_complete());
        assert_eq!(buffer.read(0, 9), (1..=10).collect::<Vec<u8>>());
        assert_eq!(buffer.next_gap(0, 9), None);
    }

    /// A piece arriving over bytes already here keeps what is there and adds only what is new.
    #[test]
    fn media_buffer_write_never_overwrites() {
        let mut buffer = MediaBuffer::pending(6);
        buffer.write(0, &[1, 2, 3]);
        buffer.write(2, &[9, 4, 5]);
        assert_eq!(buffer.read(0, 4), vec![1, 2, 3, 4, 5]);

        // Bytes that would run into a later extent stop where it starts
        let mut buffer = MediaBuffer::pending(6);
        buffer.write(4, &[5, 6]);
        buffer.write(0, &[1, 2, 3, 4, 9, 9]);
        assert_eq!(buffer.read(0, 5), vec![1, 2, 3, 4, 5, 6]);
        assert!(buffer.is_complete());
    }

    /// A typical song is 2-4 MB. A fixed 4 MiB range size meant exactly those never split at
    /// all, which is why a skip waited on the one throttled stream this is meant to avoid.
    #[test]
    fn audio_chunk_size_splits_a_song_and_bounds_the_extremes() {
        let song = 2_562_800_u64;
        let size = audio_chunk_size(song);
        assert!(size >= AUDIO_MIN_CHUNK_BYTES);
        assert!(song.div_ceil(size) > 1, "a song must split into several ranges");

        // Tiny files stay at the floor rather than becoming a swarm of requests.
        assert_eq!(audio_chunk_size(600_000), AUDIO_MIN_CHUNK_BYTES);
        // Large files stay capped rather than becoming a few huge ones.
        assert_eq!(audio_chunk_size(500 * 1024 * 1024), OFFLINE_CHUNK_BYTES);
    }

    /// The whole point of the jar: a rotated value replaces the stale one, a new value joins,
    /// an unchanged value reports no change, and a tombstone drops the cookie.
    #[test]
    fn set_cookie_merges_rotations_into_the_stored_session() {
        let mut pairs = parse_cookie_header("SAPISID=keepme; SIDCC=old; YSC=stay");

        assert!(apply_set_cookie(
            &mut pairs,
            "SIDCC=new; expires=Fri, 01 Jan 2027 00:00:00 GMT; path=/; secure",
        ));
        assert!(apply_set_cookie(&mut pairs, "__Secure-3PSIDTS=fresh; path=/"));
        // Same value again is not a rotation, and must not trigger a keyring write.
        assert!(!apply_set_cookie(&mut pairs, "SIDCC=new; path=/"));
        // Order is preserved, so a merged header still reads like the one YouTube issued.
        assert_eq!(
            serialize_cookie_pairs(&pairs),
            "SAPISID=keepme; SIDCC=new; YSC=stay; __Secure-3PSIDTS=fresh"
        );

        assert!(apply_set_cookie(
            &mut pairs,
            "YSC=EXPIRED; expires=Thu, 01 Jan 1970 00:00:00 GMT",
        ));
        assert_eq!(
            serialize_cookie_pairs(&pairs),
            "SAPISID=keepme; SIDCC=new; __Secure-3PSIDTS=fresh"
        );
        // Dropping something already gone is not a change either.
        assert!(!apply_set_cookie(&mut pairs, "YSC=; max-age=0"));
    }

    /// Which rotations may wait for the interval. Getting this backwards is what made a session
    /// look lost overnight: a `PSIDTS` rotated at 23:58 and never written before the app quit.
    #[test]
    fn only_the_noisy_cookies_may_be_persisted_late() {
        assert!(is_slow_persist_cookie("SIDCC=abc; path=/; secure"));
        assert!(is_slow_persist_cookie("__Secure-3PSIDCC=abc; path=/"));
        assert!(!is_slow_persist_cookie("__Secure-3PSIDTS=fresh; path=/"));
        assert!(!is_slow_persist_cookie("SAPISID=abc; path=/"));
        // A tombstone for a credential still has to be stored at once: it is a real change.
        assert!(!is_slow_persist_cookie("__Secure-1PSID=; max-age=0"));
        assert!(!is_slow_persist_cookie("not-a-cookie"));
    }

    /// Same account or not, which decides whether signing in again costs a full resync.
    #[test]
    fn account_identity_survives_a_renewal_and_changes_with_the_account() {
        let lapsed = "SAPISID=account-one; SIDCC=stale; __Secure-3PSIDTS=stale";
        let renewed = "SAPISID=account-one; SIDCC=fresh; __Secure-3PSIDTS=fresh";
        let other = "SAPISID=account-two; SIDCC=fresh";

        assert_eq!(
            cookie_account_identity(lapsed),
            cookie_account_identity(renewed),
            "a re-minted session is the same account and must keep its cache"
        );
        assert_ne!(cookie_account_identity(lapsed), cookie_account_identity(other));
        // Fallbacks, for a cookie set that carries no plain SAPISID.
        assert_eq!(
            cookie_account_identity("__Secure-3PAPISID=third-party; YSC=x").as_deref(),
            Some("third-party")
        );
        // Nothing to compare is treated as a different account by the caller, so it must be None
        // rather than an empty string that would match another empty one.
        assert_eq!(cookie_account_identity("SAPISID=; YSC=x"), None);
        assert_eq!(cookie_account_identity("YSC=x"), None);
    }

    #[test]
    fn only_youtube_hosts_touch_the_cookie_jar() {
        let youtube = |url: &str| is_youtube_cookie_host(&url::Url::parse(url).unwrap());
        assert!(youtube("https://music.youtube.com/youtubei/v1/browse"));
        assert!(youtube("https://youtube.com/"));
        // A suffix match alone would hand the session to a lookalike domain.
        assert!(!youtube("https://notyoutube.com/"));
        assert!(!youtube("https://rr6.googlevideo.com/videoplayback"));
    }

    #[test]
    fn audio_url_with_range_appends_without_disturbing_the_signature() {
        // The real shape: a query already present, so the range joins it with `&`.
        assert_eq!(
            audio_url_with_range("https://rr6.googlevideo.com/videoplayback?itag=140", 0, 1023),
            "https://rr6.googlevideo.com/videoplayback?itag=140&range=0-1023"
        );
        // A URL with no query at all still has to produce a valid one.
        assert_eq!(
            audio_url_with_range("https://rr6.googlevideo.com/videoplayback", 10, 20),
            "https://rr6.googlevideo.com/videoplayback?range=10-20"
        );
        // Percent-encoded values must survive untouched — re-encoding `==` breaks the signature.
        assert!(audio_url_with_range("https://x/y?xpc=EgVo2aDSNQ%3D%3D", 0, 1)
            .contains("xpc=EgVo2aDSNQ%3D%3D"));
    }

    #[test]
    fn signed_content_length_reads_clen() {
        let url = url::Url::parse("https://rr6.googlevideo.com/videoplayback?itag=140&clen=4844302")
            .expect("test URL parses");
        assert_eq!(signed_content_length(&url), Some(4_844_302));

        let no_clen =
            url::Url::parse("https://rr6.googlevideo.com/videoplayback?itag=140").expect("parses");
        assert_eq!(signed_content_length(&no_clen), None);
    }


    #[test]
    fn sanitize_log_url_withholds_credentials_and_keeps_diagnostics() {
        let sanitized = sanitize_log_url(
            "https://rr6---sn-2uja.googlevideo.com/videoplayback\
             ?expire=1790000000&itag=140&mime=audio%2Fmp4&clen=4844302&c=WEB_REMIX&cver=1.0\
             &ip=203.0.113.7&sig=SECRETSIG&lsig=SECRETLSIG&pot=SECRETPOT&n=SECRETN",
        );

        // Nothing secret survives, checked by value so a future allowlist edit that admits one
        // of these fails here rather than in production.
        for secret in ["SECRETSIG", "SECRETLSIG", "SECRETPOT", "SECRETN", "203.0.113.7"] {
            assert!(!sanitized.contains(secret), "leaked {secret} in {sanitized}");
        }

        // ...and the parameters that explain a 403 are still readable.
        for kept in ["expire=1790000000", "itag=140", "c=WEB_REMIX", "cver=1.0", "clen=4844302"] {
            assert!(sanitized.contains(kept), "dropped {kept} from {sanitized}");
        }

        // Withheld values report their length, which is how a present-but-truncated signature is
        // told apart from a missing one.
        assert!(sanitized.contains("sig=[9ch]"), "{sanitized}");
        assert!(sanitized.contains("https://rr6---sn-2uja.googlevideo.com/videoplayback?"));
    }

    #[test]
    fn sanitize_log_url_rejects_unparseable_input() {
        assert_eq!(sanitize_log_url("not a url"), "[redacted-url]");
    }

    #[test]
    fn error_cause_chain_walks_the_full_source_chain() {
        #[derive(Debug)]
        struct Wrapped(&'static str, Option<Box<dyn std::error::Error>>);
        impl std::fmt::Display for Wrapped {
            fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                write!(f, "{}", self.0)
            }
        }
        impl std::error::Error for Wrapped {
            fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
                self.1.as_deref()
            }
        }

        let dns_failure = Wrapped("dns error: no such host", None);
        let send_failure = Wrapped(
            "error sending request for url (https://www.youtube.com/iframe_api)",
            Some(Box::new(dns_failure)),
        );

        assert_eq!(
            error_cause_chain(&send_failure),
            "error sending request for url (https://www.youtube.com/iframe_api) -> caused by: dns error: no such host",
            "the underlying DNS/TLS/connection cause must survive, not just reqwest's wrapper text",
        );

        let bare = Wrapped("connection refused", None);
        assert_eq!(error_cause_chain(&bare), "connection refused");
    }

    /// A cookie header carrying just enough for `cookie_account_identity` to fingerprint it.
    fn fake_account_cookie(sapisid: &str) -> String {
        format!("SAPISID={sapisid}; HSID=unrelated")
    }

    #[test]
    fn generate_slot_id_is_32_lowercase_hex_chars_and_not_a_repeat() {
        let a = generate_slot_id();
        let b = generate_slot_id();
        assert_eq!(a.len(), 32, "16 bytes, hex-encoded: {a}");
        assert!(a.chars().all(|c| c.is_ascii_hexdigit() && !c.is_ascii_uppercase()), "{a}");
        assert_ne!(a, b, "two draws from OsRng landing on the same 128 bits would mean it is broken");
    }

    #[test]
    fn login_partition_directory_name_keeps_the_legacy_slot_unsuffixed_and_others_distinct() {
        assert_eq!(login_partition_directory_name(LEGACY_ACCOUNT_SLOT_ID), "youtube-login-webview");
        let a = generate_slot_id();
        let b = generate_slot_id();
        assert_eq!(login_partition_directory_name(&a), format!("youtube-login-webview-{a}"));
        assert_ne!(
            login_partition_directory_name(&a),
            login_partition_directory_name(&b),
            "two stored accounts must never resolve to the same webview partition",
        );
    }

    #[test]
    fn from_legacy_cookie_becomes_one_active_account_pinned_to_the_legacy_slot() {
        let store = YoutubeAccountStore::from_legacy_cookie(
            &fake_account_cookie("alice"),
            LEGACY_ACCOUNT_SLOT_ID.to_string(),
        );
        assert_eq!(store.accounts.len(), 1);
        assert_eq!(store.active_slot_id.as_deref(), Some(LEGACY_ACCOUNT_SLOT_ID));
        assert_eq!(store.active().unwrap().slot_id, LEGACY_ACCOUNT_SLOT_ID);
    }

    #[test]
    fn upsert_new_identity_creates_a_slot_and_reports_the_account_as_changed() {
        let mut store = YoutubeAccountStore::default();
        let (slot_id, changed) =
            store.upsert_signed_in_account(&fake_account_cookie("alice"), "candidate-1".to_string());
        assert_eq!(slot_id, "candidate-1");
        assert!(changed, "the very first sign-in is always a change from signed-out");
        assert_eq!(store.accounts.len(), 1);
        assert_eq!(store.active_slot_id.as_deref(), Some("candidate-1"));
    }

    #[test]
    fn upsert_same_identity_while_already_active_refreshes_in_place_without_a_duplicate() {
        let mut store = YoutubeAccountStore::default();
        store.upsert_signed_in_account(&fake_account_cookie("alice"), "candidate-1".to_string());

        // Re-authenticating the same Google account through a brand new candidate partition
        // (a lapsed-session renewal) must find the existing slot, not create a second one.
        let (slot_id, changed) = store.upsert_signed_in_account(
            &fake_account_cookie("alice"),
            "candidate-2-unused".to_string(),
        );
        assert_eq!(slot_id, "candidate-1", "must land back on the original slot, not the throwaway candidate");
        assert!(!changed, "same account, still active: not a change the caller should resync for");
        assert_eq!(store.accounts.len(), 1, "must not create a duplicate slot for the same identity");
    }

    #[test]
    fn upsert_a_second_known_identity_switches_and_reports_changed() {
        let mut store = YoutubeAccountStore::default();
        let (alice_slot, _) =
            store.upsert_signed_in_account(&fake_account_cookie("alice"), "candidate-1".to_string());
        store.upsert_signed_in_account(&fake_account_cookie("bob"), "candidate-2".to_string());

        // Signing back in as alice (already stored, but not currently active) must switch to
        // her slot and report a change, even though her identity was already known.
        let (slot_id, changed) =
            store.upsert_signed_in_account(&fake_account_cookie("alice"), "candidate-3-unused".to_string());
        assert_eq!(slot_id, alice_slot);
        assert!(changed, "switching back to a different stored account is a change");
        assert_eq!(store.accounts.len(), 2, "still exactly the two real accounts, no throwaway slots kept");
    }

    #[test]
    fn remove_falls_back_to_another_stored_account_when_the_active_one_is_removed() {
        let mut store = YoutubeAccountStore::default();
        let (alice_slot, _) =
            store.upsert_signed_in_account(&fake_account_cookie("alice"), "candidate-1".to_string());
        let (bob_slot, _) =
            store.upsert_signed_in_account(&fake_account_cookie("bob"), "candidate-2".to_string());
        assert_eq!(store.active_slot_id.as_deref(), Some(bob_slot.as_str()));

        let (new_active_cookie, existed) = store.remove(&bob_slot);
        assert!(existed);
        assert_eq!(store.accounts.len(), 1);
        assert_eq!(store.active_slot_id.as_deref(), Some(alice_slot.as_str()), "falls back to whoever is left");
        assert_eq!(new_active_cookie.as_deref(), Some(fake_account_cookie("alice").as_str()));
    }

    #[test]
    fn remove_the_last_account_leaves_the_store_cleanly_empty() {
        let mut store = YoutubeAccountStore::default();
        let (slot_id, _) =
            store.upsert_signed_in_account(&fake_account_cookie("alice"), "candidate-1".to_string());
        let (new_active_cookie, existed) = store.remove(&slot_id);
        assert!(existed);
        assert!(new_active_cookie.is_none());
        assert!(store.active_slot_id.is_none());
        assert!(store.accounts.is_empty());
        assert!(store.active().is_none());
    }

    #[test]
    fn remove_an_unknown_slot_is_a_harmless_no_op() {
        let mut store = YoutubeAccountStore::default();
        store.upsert_signed_in_account(&fake_account_cookie("alice"), "candidate-1".to_string());
        let before = store.accounts.len();
        let (new_active_cookie, existed) = store.remove("never-stored");
        assert!(!existed);
        assert_eq!(store.accounts.len(), before, "removing a slot that was never there must not disturb the rest");
        assert!(new_active_cookie.is_some(), "the real account is still active throughout");
    }

    #[test]
    fn switch_active_moves_to_a_stored_slot_and_rejects_an_unknown_one_without_side_effects() {
        let mut store = YoutubeAccountStore::default();
        let (alice_slot, _) =
            store.upsert_signed_in_account(&fake_account_cookie("alice"), "candidate-1".to_string());
        store.upsert_signed_in_account(&fake_account_cookie("bob"), "candidate-2".to_string());

        let cookie = store.switch_active(&alice_slot);
        assert_eq!(cookie.as_deref(), Some(fake_account_cookie("alice").as_str()));
        assert_eq!(store.active_slot_id.as_deref(), Some(alice_slot.as_str()));

        let previously_active = store.active_slot_id.clone();
        assert!(
            store.switch_active("never-stored").is_none(),
            "switching to an account removed elsewhere in the meantime must fail cleanly",
        );
        assert_eq!(store.active_slot_id, previously_active, "a failed switch must not change who is active");
    }

    #[test]
    fn active_self_heals_when_the_recorded_active_slot_no_longer_exists() {
        let mut store = YoutubeAccountStore::default();
        store.upsert_signed_in_account(&fake_account_cookie("alice"), "candidate-1".to_string());
        // Simulates corrupt/stale state rather than reachable through the public methods.
        store.active_slot_id = Some("does-not-exist".to_string());
        assert!(
            store.active().is_some(),
            "at least one account is stored, so this should read as signed in as *someone*, not signed out",
        );
    }

    #[test]
    fn account_store_round_trips_through_json() {
        let mut store = YoutubeAccountStore::default();
        store.upsert_signed_in_account(&fake_account_cookie("alice"), "candidate-1".to_string());
        let json = serde_json::to_string(&store).unwrap();
        let restored: YoutubeAccountStore = serde_json::from_str(&json).unwrap();
        assert_eq!(restored.active_slot_id, store.active_slot_id);
        assert_eq!(restored.accounts.len(), store.accounts.len());
        assert_eq!(restored.accounts[0].cookie, store.accounts[0].cookie);
    }

    #[test]
    fn a_bare_legacy_cookie_header_is_not_mistaken_for_json_and_vice_versa() {
        // This is the exact discriminator `load_account_store` relies on to tell a pre-existing
        // install's bare cookie header apart from the new JSON shape.
        let legacy_blob = fake_account_cookie("alice");
        assert!(serde_json::from_str::<YoutubeAccountStore>(&legacy_blob).is_err());

        let store = YoutubeAccountStore::from_legacy_cookie(&legacy_blob, LEGACY_ACCOUNT_SLOT_ID.to_string());
        let json_blob = serde_json::to_string(&store).unwrap();
        assert!(serde_json::from_str::<YoutubeAccountStore>(&json_blob).is_ok());
    }

    /// A decode failure's log line has to be readable whichever way the response was wrong —
    /// binary garbage as hex, an error page as text.
    #[test]
    fn bytes_preview_reads_both_binary_and_text_content() {
        let matroska_start = bytes_preview(&[0x1A, 0x45, 0xDF, 0xA3, 0x00, 0x01]);
        assert!(matroska_start.contains("hex=1a45dfa30001"));

        let error_page = bytes_preview(b"{\"error\":\"forbidden\"}");
        assert!(error_page.contains("text=\"{\\\"error\\\":\\\"forbidden\\\"}\""));

        assert_eq!(bytes_preview(&[]), "0 bytes, starts hex= text=\"\"");
    }
}
