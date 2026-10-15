// Copyright (C) 2026 George Dobreff ("Witcher") and contributors
// SPDX-License-Identifier: GPL-3.0-only

// Keeps the thumbnail cache from ever showing an old picture for a file (taris-thumbnails.service,
// as root). GNOME's thumbnails (~/.cache/thumbnails, shared by Nautilus, file dialogs and other
// apps through GLib) count as current while the file's path and modification time, in seconds,
// match the ones they were made for; a file renamed, copied with its times kept or rewritten
// within the same second matches too, and its old picture stays. So whenever a file appears at a
// path (created, renamed or moved there), is written or has its times changed, on any filesystem
// the kernel reports changes for (fanotify), its thumbnails are deleted from every account's
// cache, and everything cached under a directory that's renamed or moved. A drive mounted may
// have changed elsewhere: everything cached under it goes. The kernel only reports on a whole
// filesystem from its top: for btrfs, whose sub-volumes (@, @home) are what's mounted, the top is
// mounted read-only in the service's own mount namespace (PrivateMounts=), seen by nothing else,
// and unmounted once the filesystem is. When changes may have been missed
// (events lost, or the last run didn't stop cleanly), every cached thumbnail goes. Thumbnails are
// deleted as the account they belong to, never as root; they're made again from the file.
// Usage: /usr/lib/taris/thumbnails
//        /usr/lib/taris/thumbnails --cache <dir>   (just that cache, as the caller: for testing)

#include <fcntl.h>
#include <grp.h>
#include <poll.h>
#include <pwd.h>
#include <signal.h>
#include <sys/fanotify.h>
#include <sys/fsuid.h>
#include <sys/mount.h>
#include <sys/signalfd.h>
#include <sys/stat.h>
#include <sys/statfs.h>
#include <unistd.h>

#include <glib.h>

#include <cerrno>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <dirent.h>
#include <map>
#include <set>
#include <sstream>
#include <string>
#include <vector>

namespace {

// Where the thumbnail factory keeps thumbnails (one folder per size, and the ones it failed at)
const char* const kSizes[] = { "normal", "large", "x-large", "xx-large", "fail/gnome-thumbnail-factory" };

// Filesystems reported on (the ones that hold people's files); others are skipped
const std::set<std::string> kWatched = { "btrfs", "ext4", "xfs", "f2fs", "vfat", "exfat", "ntfs3", "tmpfs" };

// Where this run's clean stop is recorded: without it, the last run may have missed changes
const char* const kCleanStop = "/var/lib/taris-thumbnails/clean-stop";

// Where tops of filesystems are mounted (RuntimeDirectory=, in the service's own mount namespace)
const char* const kTops = "/run/taris-thumbnails";

struct Account {
    uid_t uid;
    gid_t gid;
    std::string cache; // its thumbnail cache, without a trailing slash
};

// Where a filesystem's own folders are mounted: its root folder (root, as /proc/self/mountinfo
// has it) shows at point
struct Mount {
    std::string root;
    std::string point;
};

// A filesystem reported on: its top mounted at anchor (open as fd), every mount of it
struct Filesystem {
    std::string device; // major:minor
    std::string anchor;
    bool ownAnchor = false; // the top mounted here, for the reports
    // Open only for a top mounted here: one held open elsewhere would keep a drive from being
    // unmounted
    int fd = -1;
    fsid_t fsid {};
    std::vector<Mount> mounts;
};

bool testing = false;
std::string testCache;
std::vector<Account> accounts;
std::vector<Filesystem> filesystems;
std::set<std::string> mountPoints;
int fan = -1;

// Every cached thumbnail by the file URI it was made for: what a directory's covers
std::multimap<std::string, std::pair<size_t, std::string>> cached;

void logLine(const std::string& line) {
    std::fprintf(stderr, "%s\n", line.c_str());
}

// File operations as the account (its permissions, not root's), back to root after
class AsAccount {
public:
    explicit AsAccount(const Account& account) {
        if (testing)
            return;
        setfsgid(account.gid);
        setfsuid(account.uid);
    }

    ~AsAccount() {
        if (testing)
            return;
        setfsuid(0);
        setfsgid(0);
    }

    AsAccount(const AsAccount&) = delete;
    AsAccount& operator=(const AsAccount&) = delete;
};

std::string uriFor(const std::string& path) {
    gchar* uri = g_filename_to_uri(path.c_str(), nullptr, nullptr);
    if (!uri)
        return {};
    std::string result(uri);
    g_free(uri);
    return result;
}

// The URI a thumbnail was made for (its PNG's Thumb::URI text), or "" when it can't be read
std::string thumbnailUri(const std::string& file) {
    const int fd = open(file.c_str(), O_RDONLY | O_CLOEXEC | O_NOFOLLOW);
    if (fd < 0)
        return {};
    std::string data(256 * 1024, '\0');
    size_t got = 0;
    for (ssize_t n; got < data.size() && (n = read(fd, data.data() + got, data.size() - got)) > 0;)
        got += static_cast<size_t>(n);
    close(fd);
    data.resize(got);

    if (data.size() < 8 || data.compare(0, 8, "\x89PNG\r\n\x1a\n") != 0)
        return {};
    for (size_t at = 8; at + 12 <= data.size();) {
        const auto* p = reinterpret_cast<const unsigned char*>(data.data() + at);
        const size_t length = (size_t(p[0]) << 24) | (size_t(p[1]) << 16) | (size_t(p[2]) << 8) | p[3];
        const std::string type = data.substr(at + 4, 4);
        if (at + 12 + length > data.size() || type == "IEND")
            break;
        if (type == "tEXt") {
            const std::string text = data.substr(at + 8, length);
            const size_t zero = text.find('\0');
            if (zero != std::string::npos && text.compare(0, zero, "Thumb::URI") == 0)
                return text.substr(zero + 1);
        }
        at += 12 + length;
    }
    return {};
}

// The account whose cache a path is in, or -1
long cacheOwner(const std::string& path) {
    for (size_t i = 0; i < accounts.size(); i++)
        if (path.compare(0, accounts[i].cache.size() + 1, accounts[i].cache + "/") == 0)
            return static_cast<long>(i);
    return -1;
}

void learnThumbnail(size_t account, const std::string& file) {
    const std::string uri = thumbnailUri(file);
    if (uri.empty())
        return;
    auto [first, last] = cached.equal_range(uri);
    for (auto it = first; it != last; ++it)
        if (it->second.second == file)
            return;
    cached.emplace(uri, std::make_pair(account, file));
}

// Every account's cached thumbnails, read again
void learnAll() {
    cached.clear();
    for (size_t i = 0; i < accounts.size(); i++) {
        AsAccount as(accounts[i]);
        for (const char* size : kSizes) {
            const std::string dir = accounts[i].cache + "/" + size;
            DIR* d = opendir(dir.c_str());
            if (!d)
                continue;
            while (const dirent* entry = readdir(d)) {
                const std::string name = entry->d_name;
                if (name.size() > 4 && name.compare(name.size() - 4, 4, ".png") == 0)
                    learnThumbnail(i, dir + "/" + name);
            }
            closedir(d);
        }
    }
}

// The thumbnails made for one file URI, in every account
void forgetUri(const std::string& uri) {
    gchar* md5 = g_compute_checksum_for_string(G_CHECKSUM_MD5, uri.c_str(), -1);
    const std::string name = std::string(md5) + ".png";
    g_free(md5);
    for (const Account& account : accounts) {
        AsAccount as(account);
        for (const char* size : kSizes)
            unlink((account.cache + "/" + size + "/" + name).c_str());
    }
    auto [first, last] = cached.equal_range(uri);
    for (auto it = first; it != last; ++it) {
        AsAccount as(accounts[it->second.first]);
        unlink(it->second.second.c_str());
    }
    cached.erase(first, last);
}

// A directory's thumbnails and those of everything under it
void forgetUnder(const std::string& dirUri) {
    forgetUri(dirUri);
    const std::string prefix = dirUri.back() == '/' ? dirUri : dirUri + "/";
    for (auto it = cached.lower_bound(prefix); it != cached.end() && it->first.compare(0, prefix.size(), prefix) == 0;) {
        AsAccount as(accounts[it->second.first]);
        unlink(it->second.second.c_str());
        it = cached.erase(it);
    }
}

// Every cached thumbnail, in every account
void forgetAll() {
    for (const Account& account : accounts) {
        AsAccount as(account);
        for (const char* size : kSizes) {
            const std::string dir = account.cache + "/" + size;
            DIR* d = opendir(dir.c_str());
            if (!d)
                continue;
            while (const dirent* entry = readdir(d))
                if (entry->d_name[0] != '.')
                    unlinkat(dirfd(d), entry->d_name, 0);
            closedir(d);
        }
    }
    cached.clear();
}

// People's accounts (the user ids useradd gives them) and their caches
void readAccounts() {
    accounts.clear();
    if (testing) {
        accounts.push_back({ getuid(), getgid(), testCache });
        return;
    }
    setpwent();
    while (const passwd* pw = getpwent())
        if (pw->pw_uid >= 1000 && pw->pw_uid < 60000 && pw->pw_dir && pw->pw_dir[0] == '/')
            accounts.push_back({ pw->pw_uid, pw->pw_gid, std::string(pw->pw_dir) + "/.cache/thumbnails" });
    endpwent();
}

std::string unescapeMountPath(const std::string& field) {
    std::string out;
    for (size_t i = 0; i < field.size(); i++) {
        if (field[i] == '\\' && i + 3 < field.size()) {
            out += static_cast<char>(std::stoi(field.substr(i + 1, 3), nullptr, 8));
            i += 3;
        } else {
            out += field[i];
        }
    }
    return out;
}

struct MountLine {
    std::string device;
    std::string root;
    std::string point;
    std::string type;
    std::string source;
};

std::vector<MountLine> readMountTable() {
    std::vector<MountLine> lines;
    FILE* f = std::fopen("/proc/self/mountinfo", "re");
    if (!f)
        return lines;
    char* line = nullptr;
    size_t size = 0;
    while (getline(&line, &size, f) > 0) {
        // id parent major:minor root point options [optional fields] - type source super-options
        std::istringstream in(line);
        MountLine m;
        std::string id, parent, options, field;
        in >> id >> parent >> m.device >> m.root >> m.point >> options;
        while (in >> field && field != "-") {}
        in >> m.type >> m.source;
        m.root = unescapeMountPath(m.root);
        m.point = unescapeMountPath(m.point);
        m.source = unescapeMountPath(m.source);
        lines.push_back(m);
    }
    std::free(line);
    std::fclose(f);
    return lines;
}

bool isOwnTop(const std::string& point) {
    const std::string tops = std::string(kTops) + "/";
    return point.compare(0, tops.size(), tops) == 0;
}

void dropFilesystem(Filesystem& fs) {
    if (fs.fd >= 0)
        close(fs.fd);
    if (fs.ownAnchor) {
        umount2(fs.anchor.c_str(), MNT_DETACH);
        rmdir(fs.anchor.c_str());
    }
}

// The filesystems reported on, read again: new ones are watched (and what's cached under where
// they show goes), and tops mounted here for ones no longer mounted elsewhere are unmounted
void readMounts(bool startup) {
    const std::vector<MountLine> table = readMountTable();

    // Every mount of each filesystem, and its top where something has it mounted
    std::map<std::string, Filesystem> found;
    std::map<std::string, MountLine> source;
    std::set<std::string> points;
    for (const MountLine& m : table) {
        if (!kWatched.count(m.type))
            continue;
        Filesystem& fs = found[m.device];
        fs.device = m.device;
        if (isOwnTop(m.point)) {
            fs.anchor = m.point;
            fs.ownAnchor = true;
            continue;
        }
        fs.mounts.push_back({ m.root, m.point });
        source.emplace(m.device, m);
        points.insert(m.point);
        if (m.root == "/" && (fs.anchor.empty() || fs.ownAnchor)) {
            fs.anchor = m.point;
            fs.ownAnchor = false;
        }
    }

    // Tops mounted here before: kept while their filesystem is still mounted somewhere else
    for (Filesystem& old : filesystems) {
        const auto it = found.find(old.device);
        if (it == found.end() || it->second.mounts.empty() || it->second.anchor != old.anchor) {
            dropFilesystem(old);
            if (it != found.end() && it->second.anchor == old.anchor) {
                it->second.anchor.clear();
                it->second.ownAnchor = false;
            }
        } else if (old.fd >= 0) {
            close(old.fd);
        }
    }
    filesystems.clear();

    for (auto& [device, fs] : found) {
        if (fs.mounts.empty())
            continue;
        const MountLine& m = source.at(device);
        // No mount shows this filesystem's top (btrfs sub-volumes): it's mounted here
        if (fs.anchor.empty() && m.type == "btrfs" && geteuid() == 0) {
            std::string dir = std::string(kTops) + "/" + device;
            dir[dir.find(':')] = '-';
            mkdir(dir.c_str(), 0700);
            if (mount(m.source.c_str(), dir.c_str(), "btrfs", MS_RDONLY | MS_NOSUID | MS_NODEV | MS_NOEXEC,
                    "subvolid=5") != 0) {
                logLine("can't reach the top of " + m.source + ": " + std::strerror(errno));
                rmdir(dir.c_str());
                continue;
            }
            fs.anchor = dir;
            fs.ownAnchor = true;
        }
        if (fs.anchor.empty()) {
            logLine("not watching " + fs.mounts.front().point + ": its top isn't mounted");
            continue;
        }
        struct statfs st {};
        if (statfs(fs.anchor.c_str(), &st) != 0) {
            if (fs.ownAnchor)
                dropFilesystem(fs);
            continue;
        }
        fs.fsid = st.f_fsid;
        fs.fd = fs.ownAnchor ? open(fs.anchor.c_str(), O_RDONLY | O_DIRECTORY | O_CLOEXEC) : -1;
        const uint64_t mask = FAN_CREATE | FAN_ATTRIB | FAN_CLOSE_WRITE | FAN_RENAME | FAN_ONDIR;
        if (fanotify_mark(fan, FAN_MARK_ADD | FAN_MARK_FILESYSTEM, mask, AT_FDCWD, fs.anchor.c_str()) != 0) {
            logLine("not watching " + fs.mounts.front().point + ": " + std::strerror(errno));
            dropFilesystem(fs);
            continue;
        }
        filesystems.push_back(fs);
    }

    // Mounted since: it may have changed elsewhere
    if (!startup)
        for (const std::string& point : points)
            if (!mountPoints.count(point))
                forgetUnder(uriFor(point));
    mountPoints = std::move(points);
}

// The paths a directory handle with a name in it stands for: one for each mount of the folder
std::vector<std::string> pathsFor(const __kernel_fsid_t& fsid, file_handle* handle, const char* name) {
    std::vector<std::string> paths;
    for (const Filesystem& fs : filesystems) {
        if (std::memcmp(&fs.fsid, &fsid, sizeof fsid) != 0)
            continue;
        const int anchor = fs.fd >= 0 ? fs.fd : open(fs.anchor.c_str(), O_RDONLY | O_DIRECTORY | O_CLOEXEC);
        if (anchor < 0)
            continue;
        const int fd = open_by_handle_at(anchor, handle, O_PATH | O_CLOEXEC);
        if (anchor != fs.fd)
            close(anchor);
        if (fd < 0)
            continue;
        char dir[PATH_MAX];
        const std::string link = "/proc/self/fd/" + std::to_string(fd);
        const ssize_t n = readlink(link.c_str(), dir, sizeof dir - 1);
        close(fd);
        if (n <= 0)
            continue;
        std::string full(dir, static_cast<size_t>(n));
        if (full.size() > 10 && full.compare(full.size() - 10, 10, " (deleted)") == 0)
            continue;
        if (std::strcmp(name, ".") != 0)
            full += (full == "/" ? "" : "/") + std::string(name);

        // Where it is in the filesystem, then everywhere that shows
        std::string inside = fs.anchor == "/" ? full : full.substr(std::min(full.size(), fs.anchor.size()));
        if (full.compare(0, fs.anchor.size(), fs.anchor) != 0)
            continue;
        if (inside.empty())
            inside = "/";
        for (const Mount& m : fs.mounts) {
            std::string path;
            if (m.root == "/")
                path = m.point == "/" ? inside : m.point + (inside == "/" ? "" : inside);
            else if (inside == m.root)
                path = m.point;
            else if (inside.compare(0, m.root.size() + 1, m.root + "/") == 0)
                path = (m.point == "/" ? "" : m.point) + inside.substr(m.root.size());
            else
                continue;
            bool seen = false;
            for (const std::string& p : paths)
                seen = seen || p == path;
            if (!seen)
                paths.push_back(path);
        }
        break;
    }
    return paths;
}

void handle(uint64_t mask, const fanotify_event_info_fid* fid, uint8_t type) {
    auto* handle = reinterpret_cast<file_handle*>(const_cast<unsigned char*>(fid->handle));
    const char* name = reinterpret_cast<const char*>(handle->f_handle + handle->handle_bytes);
    for (const std::string& path : pathsFor(fid->fsid, handle, name)) {
        // A thumbnail made: learnt, for when its file's directory moves
        if (const long owner = cacheOwner(path); owner >= 0) {
            if (type != FAN_EVENT_INFO_TYPE_OLD_DFID_NAME && path.size() > 4 &&
                path.compare(path.size() - 4, 4, ".png") == 0) {
                AsAccount as(accounts[static_cast<size_t>(owner)]);
                learnThumbnail(static_cast<size_t>(owner), path);
            }
            continue;
        }
        if (path == "/etc/passwd") {
            readAccounts();
            learnAll();
        }
        const std::string uri = uriFor(path);
        if (uri.empty())
            continue;
        if ((mask & FAN_ONDIR) && (mask & FAN_RENAME))
            forgetUnder(uri);
        else
            forgetUri(uri);
    }
}

void readEvents() {
    alignas(fanotify_event_metadata) char buffer[64 * 1024];
    for (;;) {
        const ssize_t length = read(fan, buffer, sizeof buffer);
        if (length <= 0)
            return;
        ssize_t left = length;
        for (auto* event = reinterpret_cast<fanotify_event_metadata*>(buffer); FAN_EVENT_OK(event, left);
            event = FAN_EVENT_NEXT(event, left)) {
            if (event->vers != FANOTIFY_METADATA_VERSION)
                return;
            if (event->mask & FAN_Q_OVERFLOW) {
                logLine("changes were missed: every thumbnail goes");
                forgetAll();
                continue;
            }
            const char* info = reinterpret_cast<const char*>(event + 1);
            const char* end = reinterpret_cast<const char*>(event) + event->event_len;
            while (info + sizeof(fanotify_event_info_header) <= end) {
                const auto* header = reinterpret_cast<const fanotify_event_info_header*>(info);
                if (header->len == 0)
                    break;
                if (header->info_type == FAN_EVENT_INFO_TYPE_DFID_NAME ||
                    header->info_type == FAN_EVENT_INFO_TYPE_NEW_DFID_NAME ||
                    header->info_type == FAN_EVENT_INFO_TYPE_OLD_DFID_NAME)
                    handle(event->mask, reinterpret_cast<const fanotify_event_info_fid*>(info), header->info_type);
                info += header->len;
            }
        }
    }
}

} // namespace

int main(int argc, char** argv) {
    if (argc == 3 && std::strcmp(argv[1], "--cache") == 0) {
        testing = true;
        testCache = argv[2];
    } else if (argc != 1) {
        std::fprintf(stderr, "usage: %s [--cache <dir>]\n", argv[0]);
        return 2;
    } else if (geteuid() != 0) {
        std::fprintf(stderr, "%s: needs root (it runs as taris-thumbnails.service)\n", argv[0]);
        return 1;
    } else {
        // Root's own groups would count when acting as an account
        setgroups(0, nullptr);
    }

    fan = fanotify_init(FAN_CLASS_NOTIF | FAN_CLOEXEC | FAN_NONBLOCK | FAN_REPORT_DFID_NAME_TARGET |
            (testing ? 0 : FAN_UNLIMITED_QUEUE),
        O_RDONLY | O_LARGEFILE);
    if (fan < 0) {
        std::perror("fanotify_init");
        return 1;
    }

    sigset_t signals;
    sigemptyset(&signals);
    sigaddset(&signals, SIGTERM);
    sigaddset(&signals, SIGINT);
    sigprocmask(SIG_BLOCK, &signals, nullptr);
    const int signalFd = signalfd(-1, &signals, SFD_CLOEXEC);
    const int mountsFd = open("/proc/self/mountinfo", O_RDONLY | O_CLOEXEC);

    readAccounts();
    readMounts(true);
    learnAll();
    // Watching from here on: anything before it may have been missed unless the last run stopped
    // cleanly (with nothing changing in between, the system being down)
    if (testing || unlink(kCleanStop) != 0) {
        logLine("the last run didn't stop cleanly: every thumbnail goes");
        forgetAll();
    }
    std::fprintf(stderr, "watching %zu filesystems for %zu accounts\n", filesystems.size(), accounts.size());

    pollfd fds[] = {
        { fan, POLLIN, 0 },
        { mountsFd, POLLPRI, 0 },
        { signalFd, POLLIN, 0 },
    };
    for (;;) {
        if (poll(fds, 3, -1) < 0) {
            if (errno == EINTR)
                continue;
            std::perror("poll");
            return 1;
        }
        if (fds[0].revents & POLLIN)
            readEvents();
        if (fds[1].revents & (POLLPRI | POLLERR))
            readMounts(false);
        if (fds[2].revents & POLLIN)
            break;
    }

    // Everything up to now was seen: the next run can trust what's cached
    readEvents();
    for (Filesystem& fs : filesystems)
        dropFilesystem(fs);
    if (!testing) {
        const int fd = open(kCleanStop, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0644);
        if (fd >= 0)
            close(fd);
    }
    return 0;
}
