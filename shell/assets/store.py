#!/usr/bin/env python3
# Copyright (C) 2026 George Dobreff ("Witcher") and contributors
# SPDX-License-Identifier: GPL-3.0-only

"""The Store's helper (services/AppStore.qml): runs while the Store is open, answers it over
stdin/stdout one JSON object per line, and exits when its stdin closes.

  request  {"id": n, "cmd": "home" | "category" | "search" | "app" | "installed" | "updates"
            | "install" | "remove" | "update", ...}
  reply    {"id": n, "result": ...} or {"id": n, "error": "..."}
  events   {"event": "job", "key", "state": "running" | "done" | "failed", "progress", "message"}
           {"event": "changed"}   (what's installed changed)

Apps come from three places, native first: the Arch repos (AppStream catalogue from
archlinux-appstream-data, kept to packages this system's repos have), Flathub (apps with an
aarch64 build, installed system-wide) and the AUR (search only, and only packages that build for
aarch64; built and installed by yay in a terminal, so not here). An app is {key, id, name, summary, icon, source, pkg, installed, alt}:
alt lists the same app from another source. Icons and screenshots are downloaded (JPEG XL ones
converted to PNG) into the cache, so the shell only ever shows local files.

  store.py [--ignore-aur pkg,pkg]   AUR packages never offered as updates (local builds)
"""

import gzip
import html
import json
import os
import re
import subprocess
import sys
import threading
import time
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
from concurrent.futures import ThreadPoolExecutor

CATALOG = "/usr/share/swcatalog"
FLATHUB = "https://flathub.org/api/v2"
AUR_RPC = "https://aur.archlinux.org/rpc/v5"
CACHE = os.path.join(os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache"), "taris", "store")
ARCH = "aarch64"
# Freedesktop main categories, which Flathub's categories are too
CATEGORIES = ["AudioVideo", "Development", "Education", "Game", "Graphics", "Network", "Office", "Science", "System", "Utility"]
SHOT_WIDTH = 1248  # Screenshot width for the app page (shown at about half that, at 2x)
INDEX_VERSION = 2  # Of native-index.json: a different one is built again

out_lock = threading.Lock()
pool = ThreadPoolExecutor(max_workers=8)
# The AUR packages' .SRCINFO fetches, apart from the pool: a search running on it would wait on them
srcinfo_pool = ThreadPoolExecutor(max_workers=8)
ignore_aur = set()


def tmp_for(path):
    """A temporary name only this thread writes, so threads fetching the same file don't collide"""
    return f"{path}.{os.getpid()}-{threading.get_ident()}.tmp"


def send(obj):
    with out_lock:
        sys.stdout.write(json.dumps(obj) + "\n")
        sys.stdout.flush()


def run(cmd, timeout=60):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout).stdout
    except (OSError, subprocess.TimeoutExpired):
        return ""


def http_json(url, data=None, ttl=0):
    """GET (or POST data) a JSON URL; with ttl, kept on disk that many seconds"""
    path = None
    if ttl:
        name = re.sub(r"[^A-Za-z0-9._-]", "_", url + (json.dumps(data) if data else ""))[-150:]
        path = os.path.join(CACHE, "api", name)
        try:
            if time.time() - os.path.getmtime(path) < ttl:
                with open(path) as f:
                    return json.load(f)
        except (OSError, ValueError):
            pass
    req = urllib.request.Request(url, headers={"User-Agent": "taris-store", "Accept": "application/json"})
    if data is not None:
        req.data = json.dumps(data).encode()
        req.add_header("Content-Type", "application/json")
    with urllib.request.urlopen(req, timeout=20) as r:
        result = json.load(r)
    if path:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        tmp = tmp_for(path)
        with open(tmp, "w") as f:
            json.dump(result, f)
        os.replace(tmp, path)
    return result


def aur_builds_here(r):
    """Whether an AUR package (its RPC result) builds for this machine, from the architectures
    its .SRCINFO lists (kept per package base and version, so it's fetched once a version); None
    when that can't be told"""
    base, version = r.get("PackageBase") or r["Name"], r.get("Version", "")
    path = os.path.join(CACHE, "srcinfo", re.sub(r"[^A-Za-z0-9._+-]", "_", f"{base}-{version}"))
    try:
        with open(path) as f:
            return f.read().strip() == "yes"
    except OSError:
        pass
    try:
        req = urllib.request.Request(f"https://aur.archlinux.org/cgit/aur.git/plain/.SRCINFO?h={urllib.parse.quote(base)}",
                                     headers={"User-Agent": "taris-store"})
        with urllib.request.urlopen(req, timeout=20) as f:
            arches = re.findall(r"^\s*arch = (\S+)", f.read().decode(errors="replace"), re.M)
    except OSError:
        return None
    builds = not arches or ARCH in arches or "any" in arches
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = tmp_for(path)
    with open(tmp, "w") as f:
        f.write("yes" if builds else "no")
    os.replace(tmp, path)
    return builds


def fetch_file(url, folder):
    """A local copy of an image URL (empty on failure)"""
    ext = os.path.splitext(urllib.parse.urlparse(url).path)[1] or ".png"
    name = re.sub(r"[^A-Za-z0-9._-]", "_", urllib.parse.urlparse(url).path.strip("/"))[-120:]
    path = os.path.join(CACHE, folder, name if name.endswith(ext) else name + ext)
    if os.path.exists(path):
        return path
    tmp = tmp_for(path)
    try:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        req = urllib.request.Request(url, headers={"User-Agent": "taris-store"})
        with urllib.request.urlopen(req, timeout=20) as r, open(tmp, "wb") as f:
            f.write(r.read())
        os.replace(tmp, path)
        return path
    except OSError:
        try:
            os.remove(tmp)
        except OSError:
            pass
        return path if os.path.exists(path) else ""


def jxl_png(path):
    """The catalogue's JPEG XL icons as PNG (Qt can't read JPEG XL)"""
    out = os.path.join(CACHE, "icons", os.path.basename(path)[:-4] + ".png")
    if not os.path.exists(out):
        os.makedirs(os.path.dirname(out), exist_ok=True)
        tmp = tmp_for(out) + ".png"  # djxl picks the format from the extension
        try:
            if subprocess.run(["djxl", path, tmp], capture_output=True).returncode != 0:
                return ""
            os.replace(tmp, out)
        except OSError:
            try:
                os.remove(tmp)
            except OSError:
                pass
            return out if os.path.exists(out) else ""
    return out


def html_text(s):
    """AppStream description markup (<p>, <ul><li>…) as plain text"""
    s = re.sub(r"<li>\s*", "• ", s or "")
    s = re.sub(r"</(p|li|ul|ol)>", "\n", s)
    s = html.unescape(re.sub(r"<[^>]+>", "", s))
    return re.sub(r"\n{3,}", "\n\n", "\n".join(line.strip() for line in s.splitlines())).strip()


def pick_shot(sizes):
    """Of a screenshot's sizes [(width, url)]: the one for the app page and the largest (the preview)"""
    if not sizes:
        return None
    return {"thumb": min(sizes, key=lambda x: abs(x[0] - SHOT_WIDTH))[1], "full": max(sizes, key=lambda x: x[0])[1]}


def local_shots(shots):
    """The app page's sizes downloaded; the full ones stay addresses until a preview asks (cmd_image)"""
    def one(shot):
        path = fetch_file(shot["thumb"], "shots")
        return {"thumb": path, "full": shot["full"]} if path else None
    return [s for s in pool.map(one, shots) if s]


def norm(app_id):
    return re.sub(r"\.desktop$", "", app_id or "").lower()


# ── What this system has ─────────────────────────────────────────────────────

state = {"repo": {}, "installed": {}, "foreign": set(), "flatpaks": {}}


def load_system():
    repo = {}
    for line in run(["pacman", "-Sl"]).splitlines():
        parts = line.split()
        if len(parts) >= 2:
            repo.setdefault(parts[1], parts[0])
    installed = {}
    for line in run(["pacman", "-Q"]).splitlines():
        parts = line.split()
        if len(parts) == 2:
            installed[parts[0]] = parts[1]
    flatpaks = {}
    for line in run(["flatpak", "list", "--app", "--system", "--columns=application,version"]).splitlines():
        parts = line.split("\t")
        if parts and parts[0]:
            flatpaks[parts[0]] = parts[1] if len(parts) > 1 else ""
    state.update(repo=repo, installed=installed, foreign=set(run(["pacman", "-Qqm"]).split()), flatpaks=flatpaks)


# Pending system updates (checkupdates reads a copy of the package lists, needs no root), kept a
# few minutes: a repo app can only be installed safely together with them (pacman -Syu); installing
# from outdated lists fails (the old package files are gone from the mirror) and refreshing them
# alone (-Sy) is a partial upgrade
_pending = {"count": -1, "at": 0.0}


def pending_updates(max_age=300):
    if time.time() - _pending["at"] > max_age:
        try:
            p = subprocess.run(["checkupdates"], capture_output=True, text=True, timeout=180)
            # Exit 0: updates listed, 2: none, anything else: couldn't tell
            count = len(p.stdout.split("\n")) - 1 if p.returncode == 0 else 0 if p.returncode == 2 else -1
        except (OSError, subprocess.TimeoutExpired):
            count = -1
        _pending.update(count=count, at=time.time())
    return _pending["count"]


# ── The repos' catalogue ─────────────────────────────────────────────────────

native = []
native_by_id = {}
native_by_name = {}


def parse_catalogue():
    files = sorted(os.path.join(CATALOG, "xml", f) for f in os.listdir(os.path.join(CATALOG, "xml")) if f.endswith(".xml.gz"))
    stamp = [INDEX_VERSION] + [os.path.getmtime(f) for f in files]
    index = os.path.join(CACHE, "native-index.json")
    try:
        with open(index) as f:
            data = json.load(f)
        if data["stamp"] == stamp:
            return data["apps"]
    except (OSError, ValueError, KeyError):
        pass

    lang = "{http://www.w3.org/XML/1998/namespace}lang"
    apps = []
    for file in files:
        origin = ""
        with gzip.open(file) as f:
            for event, el in ET.iterparse(f, events=("start", "end")):
                if event == "start":
                    if el.tag == "components":
                        origin = el.get("origin", "")
                    continue
                if el.tag != "component":
                    continue
                if el.get("type") == "desktop-application" and el.findtext("pkgname"):
                    plain = lambda tag: next((e for e in el.findall(tag) if lang not in e.attrib), None)
                    icon, best = "", 0
                    for i in el.findall("icon"):
                        w = int(i.get("width") or 0)
                        if i.get("type") == "cached" and w > best:
                            best, icon = w, f"{CATALOG}/icons/{origin}/{w}x{i.get('height') or w}/{i.text}"
                    stock = next((i.text for i in el.findall("icon") if i.get("type") == "stock"), "")
                    shots = []
                    for s in el.findall("screenshots/screenshot"):
                        shot = pick_shot([(int(i.get("width") or 0), i.text) for i in s.findall("image") if i.text])
                        if shot:
                            shots.append(shot)
                    desc = plain("description")
                    dev = el.find("developer/name")
                    app_id = el.findtext("id") or ""
                    apps.append({
                        "id": norm(app_id) if app_id.endswith(".desktop") else app_id,
                        "name": (plain("name").text if plain("name") is not None else "") or app_id,
                        "summary": plain("summary").text if plain("summary") is not None else "",
                        "description": html_text(ET.tostring(desc, encoding="unicode")) if desc is not None else "",
                        "pkg": el.findtext("pkgname"),
                        "desktop": el.findtext("launchable[@type='desktop-id']") or "",
                        "iconFile": icon,
                        "stock": stock or "",
                        "categories": [c.text for c in el.findall("categories/category") if c.text],
                        "keywords": " ".join(k.text or "" for k in el.findall("keywords/keyword") if lang not in k.attrib),
                        "screenshots": shots[:6],
                        "developer": (dev.text if dev is not None else el.findtext("developer_name")) or "",
                        "homepage": el.findtext("url[@type='homepage']") or "",
                        "license": el.findtext("project_license") or "",
                    })
                el.clear()
    os.makedirs(CACHE, exist_ok=True)
    with open(index + ".tmp", "w") as f:
        json.dump({"stamp": stamp, "apps": apps}, f)
    os.replace(index + ".tmp", index)
    return apps


def load_native():
    native.clear()
    native_by_id.clear()
    native_by_name.clear()
    try:
        apps = parse_catalogue()
    except OSError:
        apps = []
    for a in apps:
        if a["pkg"] in state["repo"]:  # Only what this system's repos can install
            native.append(a)
            native_by_id.setdefault(norm(a["id"]), a)
            native_by_name.setdefault(a["name"].lower(), a)


# ── App objects for the shell ────────────────────────────────────────────────

def native_card(a):
    icon = a["iconFile"]
    return {
        "key": "native:" + a["id"],
        "id": a["id"],
        "name": a["name"],
        "summary": a["summary"],
        "iconFile": icon,
        "icon": "" if icon else ("theme:" + a["stock"] if a["stock"] else ""),
        "source": "native",
        "pkg": a["pkg"],
        "desktop": a["desktop"],
        "installed": a["pkg"] in state["installed"],
        "alt": [],
    }


def flathub_card(h):
    app_id = h.get("app_id") or h.get("id", "")
    return {
        "key": "flathub:" + app_id,
        "id": app_id,
        "name": h.get("name") or app_id,
        "summary": h.get("summary") or "",
        "iconUrl": h.get("icon") or "",
        "icon": "",
        "source": "flathub",
        "pkg": app_id,
        "desktop": app_id + ".desktop",
        "installed": app_id in state["flatpaks"],
        "verified": bool(h.get("verification_verified")),
        "alt": [],
    }


def aur_card(r):
    return {
        "key": "aur:" + r["Name"],
        "id": r["Name"],
        "name": r["Name"],
        "summary": r.get("Description") or "",
        "icon": "",
        "source": "aur",
        "pkg": r["Name"],
        "desktop": "",
        "installed": r["Name"] in state["installed"],
        "version": r.get("Version", ""),
        "alt": [],
    }


def merge(natives, flathubs):
    """Native first: a Flathub app that's also native becomes the native card's alternative"""
    cards, seen = [], {}
    for a in natives:
        c = native_card(a)
        seen[c["key"]] = c
        cards.append(c)
    for h in flathubs:
        f = flathub_card(h)
        twin = native_by_id.get(norm(f["id"])) or native_by_name.get(f["name"].lower())
        if twin:
            c = seen.get("native:" + twin["id"])
            if not c:
                c = native_card(twin)
                seen[c["key"]] = c
                cards.append(c)
            if not any(x["source"] == "flathub" for x in c["alt"]):
                c["alt"].append({"source": "flathub", "pkg": f["pkg"], "key": f["key"], "installed": f["installed"]})
        else:
            cards.append(f)
    return cards


def with_icons(cards):
    """Local icon files for the cards, fetched or converted in parallel"""
    def one(c):
        # One icon failing leaves that icon blank, not the whole list
        try:
            if c.get("iconFile"):
                c["icon"] = jxl_png(c["iconFile"]) if c["iconFile"].endswith(".jxl") else c["iconFile"]
            elif c.get("iconUrl"):
                c["icon"] = fetch_file(c["iconUrl"], "icons")
        except OSError:
            c["icon"] = ""
        c.pop("iconFile", None)
        c.pop("iconUrl", None)
        return c
    return list(pool.map(one, cards))


def arm(hits):
    return [h for h in hits if ARCH in (h.get("arches") or [ARCH])]


# ── Requests ─────────────────────────────────────────────────────────────────

def cmd_home(_):
    sections = {}
    def coll(name):
        try:
            return name, arm(http_json(f"{FLATHUB}/collection/{name}?page=1&per_page=60", ttl=6 * 3600).get("hits", []))[:24]
        except (OSError, ValueError):
            return name, []
    for name, hits in pool.map(coll, ["popular", "trending", "recently-added"]):
        sections[name] = with_icons(merge([], hits))
    return sections


def cmd_category(req):
    cat = req["name"]
    try:
        hits = arm(http_json(f"{FLATHUB}/collection/category/{cat}?page=1&per_page=100", ttl=6 * 3600).get("hits", []))
    except (OSError, ValueError):
        hits = []
    popular = merge([], hits)  # Flathub's order: most installed first, natives in their place
    keys = {c["key"] for c in popular}
    rest = sorted((a for a in native if a["categories"] and a["categories"][0] == cat and "native:" + a["id"] not in keys),
                  key=lambda a: a["name"].lower())
    return with_icons(popular + [native_card(a) for a in rest][:120])


def cmd_search(req):
    q = req["q"].strip().lower()
    if not q:
        return {"apps": [], "aur": []}

    def score(a):
        name = a["name"].lower()
        if name == q:
            return 0
        if name.startswith(q):
            return 1
        if q in name:
            return 2
        if q in a["pkg"].lower() or q in a["keywords"].lower():
            return 3
        if q in a["summary"].lower():
            return 4
        return None
    found = sorted(((s, a) for a in native if (s := score(a)) is not None), key=lambda x: (x[0], x[1]["name"].lower()))

    def flathub():
        try:
            return arm(http_json(f"{FLATHUB}/search", {"query": q, "filters": [{"filterType": "arches", "value": ARCH}]}, ttl=3600).get("hits", []))[:30]
        except (OSError, ValueError):
            return []

    def aur():
        if len(q) < 2:
            return []
        try:
            res = http_json(f"{AUR_RPC}/search/{urllib.parse.quote(q)}?by=name-desc", ttl=3600).get("results", [])
        except (OSError, ValueError):
            return []
        res = [r for r in res if r["Name"] not in state["repo"]]
        # The most popular that build for this machine (one whose architectures can't be told stays:
        # its page tells again)
        res = sorted(res, key=lambda r: -float(r.get("Popularity") or 0))[:40]
        builds = list(srcinfo_pool.map(aur_builds_here, res))
        return [aur_card(r) for r, b in zip(res, builds) if b is not False][:20]

    fh, au = pool.submit(flathub), pool.submit(aur)
    apps = merge([a for _, a in found[:40]], fh.result())
    return {"apps": with_icons(apps), "aur": au.result()}


def sizes_from_pacman(text):
    info = {}
    for line in text.splitlines():
        if " : " in line:
            k, v = line.split(" : ", 1)
            info[k.strip()] = v.strip()
    return info


def cmd_app(req):
    source, pkg, app_id = req["source"], req["pkg"], req.get("appId", "")
    d = {"source": source, "pkg": pkg, "description": "", "screenshots": [], "version": "", "size": "", "developer": "",
         "homepage": "", "license": "", "buildsHere": True}
    if source == "native":
        a = next((x for x in native if x["id"] == app_id), None) or next((x for x in native if x["pkg"] == pkg), None)
        if a:
            d.update(description=a["description"], developer=a["developer"], homepage=a["homepage"], license=a["license"])
            d["screenshots"] = local_shots(a["screenshots"])
        info = sizes_from_pacman(run(["pacman", "-Si", pkg]))
        d["version"] = info.get("Version", "")
        d["size"] = info.get("Installed Size", "")
        d["license"] = d["license"] or info.get("Licenses", "")
        d["homepage"] = d["homepage"] or info.get("URL", "")
        d["installed"] = pkg in state["installed"]
        d["systemUpdates"] = pending_updates() if not d["installed"] else 0
    elif source == "flathub":
        try:
            a = http_json(f"{FLATHUB}/appstream/{urllib.parse.quote(pkg)}", ttl=6 * 3600)
        except (OSError, ValueError):
            a = {}
        try:
            s = http_json(f"{FLATHUB}/summary/{urllib.parse.quote(pkg)}", ttl=6 * 3600)
        except (OSError, ValueError):
            s = {}
        shots = []
        for sh in (a.get("screenshots") or [])[:6]:
            shot = pick_shot([(int(x.get("width") or 0), x["src"]) for x in sh.get("sizes", []) if x.get("src")])
            if shot:
                shots.append(shot)
        d.update(description=html_text(a.get("description", "")), developer=a.get("developer_name", ""),
                 homepage=(a.get("urls") or {}).get("homepage", ""), license=a.get("project_license", ""),
                 version=((a.get("releases") or [{}])[0]).get("version", ""))
        if s.get("installed_size"):
            d["size"] = f"{s['installed_size'] / 1048576:.1f} MiB"
        d["screenshots"] = local_shots(shots)
        d["installed"] = pkg in state["flatpaks"]
    elif source == "aur":
        try:
            r = (http_json(f"{AUR_RPC}/info?arg[]={urllib.parse.quote(pkg)}", ttl=3600).get("results") or [{}])[0]
        except (OSError, ValueError):
            r = {}
        d.update(description=r.get("Description", ""), version=r.get("Version", ""), homepage=r.get("URL") or "",
                 license=", ".join(r.get("License") or []), developer=r.get("Maintainer") or "",
                 votes=r.get("NumVotes", 0))
        # Whether it builds on this machine
        if r and (builds := aur_builds_here(r)) is not None:
            d["buildsHere"] = builds
        d["installed"] = pkg in state["installed"]
    return d


def read_desktop(path):
    """Name and icon of a launcher, or None when it's hidden from the app launcher"""
    name = icon = ""
    try:
        with open(path) as fh:
            for line in fh:
                if line.startswith("[") and line.strip() != "[Desktop Entry]":
                    break
                key, _, value = line.partition("=")
                value = value.strip()
                if key in ("NoDisplay", "Hidden") and value.lower() == "true":
                    return None
                if key == "Name" and not name:
                    name = value
                elif key == "Icon" and not icon:
                    icon = value
    except OSError:
        return None
    return {"name": name, "icon": icon, "desktop": os.path.basename(path)}


def find_desktop(desktop_id):
    """A launcher as the app launcher sees it: the user's own copy first, then the system's"""
    dirs = [os.environ.get("XDG_DATA_HOME") or os.path.expanduser("~/.local/share")]
    dirs += (os.environ.get("XDG_DATA_DIRS") or "/usr/local/share:/usr/share").split(":")
    for d in dirs:
        path = os.path.join(d, "applications", desktop_id)
        if os.path.exists(path):
            return path
    return None


def shown(desktop_id):
    path = find_desktop(desktop_id)
    return path is not None and read_desktop(path) is not None


def desktop_info(pkg):
    """Name and icon of a package's first shown app launcher, for apps the catalogue doesn't know"""
    for f in run(["pacman", "-Qlq", pkg]).splitlines():
        if f.startswith("/usr/share/applications/") and f.endswith(".desktop"):
            info = read_desktop(find_desktop(os.path.basename(f)) or f)
            if info:
                return info
    return None


def cmd_installed(_):
    # Apps the launcher shows (a package's hidden helpers and URL handlers aren't apps)
    cards = [native_card(a) for a in native if a["pkg"] in state["installed"]
             and (not a["desktop"] or shown(a["desktop"]))]
    seen = {c["pkg"] for c in cards}
    for pkg in sorted(state["foreign"] - seen - ignore_aur):
        info = desktop_info(pkg)
        if info:
            c = aur_card({"Name": pkg, "Description": ""})
            c.update(name=info["name"] or pkg, desktop=info["desktop"],
                     icon=info["icon"] if info["icon"].startswith("/") else "theme:" + info["icon"])
            cards.append(c)
    names = {}
    for line in run(["flatpak", "list", "--app", "--system", "--columns=application,name"]).splitlines():
        parts = line.split("\t")
        if parts and parts[0]:
            names[parts[0]] = parts[1] if len(parts) > 1 else parts[0]
    for app_id, name in names.items():
        c = flathub_card({"app_id": app_id, "name": name})
        c["icon"] = next((p for p in (f"/var/lib/flatpak/exports/share/icons/hicolor/{s}/apps/{app_id}.{e}"
                                      for s in ("128x128", "scalable", "64x64") for e in ("png", "svg")) if os.path.exists(p)), "")
        cards.append(c)
    cards = with_icons(cards)
    return sorted(cards, key=lambda c: c["name"].lower())


def cmd_updates(_):
    cards = []
    for line in run(["flatpak", "remote-ls", "--updates", "--system", "--app", "--columns=application,version,name"], timeout=120).splitlines():
        parts = line.split("\t")
        if parts and parts[0]:
            c = flathub_card({"app_id": parts[0], "name": parts[2] if len(parts) > 2 and parts[2] else parts[0]})
            c["newVersion"] = parts[1] if len(parts) > 1 else ""
            cards.append(c)
    for line in run(["yay", "-Qua"], timeout=120).splitlines():
        m = re.match(r"(\S+)\s+(\S+)\s+->\s+(\S+)", line.strip())
        if m and m.group(1) not in ignore_aur:
            c = aur_card({"Name": m.group(1), "Description": ""})
            c.update(installed=True, version=m.group(2), newVersion=m.group(3))
            info = desktop_info(m.group(1))
            if info:
                c.update(name=info["name"] or c["name"], icon=info["icon"] if info["icon"].startswith("/") else "theme:" + info["icon"])
            cards.append(c)
    return cards


# ── Installing, removing, updating (Flatpak and repo apps; the AUR goes through yay in a terminal) ──

jobs = {}


def job(key, cmds):
    def work():
        send({"event": "job", "key": key, "state": "running", "progress": -1, "message": ""})
        ok, last, errors = True, "", []
        for cmd in cmds:
            try:
                p = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL)
            except OSError as e:
                ok, last = False, str(e)
                break
            buf = b""
            while chunk := p.stdout.read1(4096):
                buf += chunk
                *lines, buf = re.split(rb"[\r\n]", buf)
                for raw in lines:
                    line = raw.decode(errors="replace").strip()
                    if not line:
                        continue
                    last = line
                    if line.lower().startswith("error:") and len(errors) < 3:
                        errors.append(line[6:].strip())
                    progress = -1
                    if m := re.search(r"\((\d+)/(\d+)\)", line):
                        progress = int(m.group(1)) / max(1, int(m.group(2)))
                    elif m := re.findall(r"(\d{1,3})%", line):
                        progress = min(100, int(m[-1])) / 100
                    send({"event": "job", "key": key, "state": "running", "progress": progress, "message": line})
            if p.wait() != 0:
                ok = False
                break
        load_system()
        jobs.pop(key, None)
        # What went wrong in the tool's own words (pacman ends with a summary that says nothing)
        message = "" if ok else ("\n".join(errors) if errors else last)
        send({"event": "job", "key": key, "state": "done" if ok else "failed", "progress": 1, "message": message})
        send({"event": "changed"})
    if key in jobs:
        return False
    jobs[key] = threading.Thread(target=work, daemon=True)
    jobs[key].start()
    return True


def cmd_install(req):
    source, pkg = req["source"], req["pkg"]
    if source == "flathub":
        return job(req["key"], [["flatpak", "install", "--system", "--noninteractive", "-y", "flathub", pkg]])
    if source == "native":
        if not re.fullmatch(r"[a-zA-Z0-9@._+-]+", pkg):
            raise ValueError(f"not a package name: {pkg}")
        # Together with the system's pending updates (see pending_updates), read from the mirrors
        # whose package lists are newest (one serving an older list than its files fails with 404s;
        # no password for that step)
        _pending["at"] = 0  # Up to date once this is done
        return job(req["key"], [["pkexec", "/usr/lib/taris/mirrors"],
                                ["pkexec", "pacman", "-Syu", "--needed", "--noconfirm", pkg]])
    raise ValueError("not installed from here")


def cmd_remove(req):
    source, pkg = req["source"], req["pkg"]
    if source == "flathub":
        return job(req["key"], [["flatpak", "uninstall", "--system", "--noninteractive", "-y", pkg],
                                ["flatpak", "uninstall", "--system", "--noninteractive", "-y", "--unused"]])
    if source == "native":
        return job(req["key"], [["pkexec", "pacman", "-Rns", "--noconfirm", pkg]])
    raise ValueError("not removed from here")


def cmd_update(req):
    if req["source"] == "flathub":
        # No pkg: every Flatpak (apps and their runtimes)
        return job(req["key"], [["flatpak", "update", "--system", "--noninteractive", "-y"] + ([req["pkg"]] if req["pkg"] else [])])
    raise ValueError("not updated from here")


def cmd_image(req):
    """A full-size screenshot for the preview, downloaded"""
    return fetch_file(req["url"], "shots-full")


def cmd_refresh(req):
    """Reads what's installed again; with pkgs, each one's installed version ("" when it isn't)"""
    load_system()
    return {pkg: state["installed"].get(pkg, "") for pkg in req.get("pkgs", [])}


COMMANDS = {"home": cmd_home, "category": cmd_category, "search": cmd_search, "app": cmd_app, "installed": cmd_installed,
            "updates": cmd_updates, "image": cmd_image, "install": cmd_install, "remove": cmd_remove, "update": cmd_update, "refresh": cmd_refresh}


def handle(req):
    try:
        send({"id": req.get("id"), "result": COMMANDS[req["cmd"]](req)})
    except Exception as e:  # The Store shows the error; the helper keeps running
        send({"id": req.get("id"), "error": f"{type(e).__name__}: {e}"})


def main():
    if "--ignore-aur" in sys.argv:
        ignore_aur.update(p for p in sys.argv[sys.argv.index("--ignore-aur") + 1].split(",") if p)
    os.makedirs(CACHE, exist_ok=True)
    load_system()
    load_native()
    send({"event": "ready"})
    for line in sys.stdin:
        try:
            req = json.loads(line)
        except ValueError:
            continue
        # Each request on its own thread: a slow search doesn't hold up the rest
        threading.Thread(target=handle, args=(req,), daemon=True).start()


if __name__ == "__main__":
    main()
