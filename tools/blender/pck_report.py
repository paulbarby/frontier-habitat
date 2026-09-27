"""List what an exported Godot 4 pack (index.pck) holds, grouped by source asset and type.

Run: python tools/blender/pck_report.py build/web_art_hab/index.pck [--top 40] [--json out.json]
Reads the pack's file table (format version 2/3: GDPC header, file base, file count, then per file: path length,
path, offset, size, md5, flags).  Imported resources (.godot/imported/<src>-<hash>.<ext>) are credited to <src>."""
import json
import os
import re
import struct
import sys
from collections import Counter


def read_table(path):
    with open(path, "rb") as fh:
        data = fh.read(64 * 1024 * 1024 if os.path.getsize(path) > 64 * 1024 * 1024 else os.path.getsize(path))
    off = data.find(b"GDPC")
    if off < 0:
        raise SystemExit("no GDPC header")
    p = off + 4
    ver, vmaj, vmin, vpat = struct.unpack_from("<4I", data, p)
    p += 16
    flags = 0
    file_base = 0
    if ver >= 2:
        flags, file_base = struct.unpack_from("<IQ", data, p)
        p += 12
    if ver >= 3:
        dir_off, = struct.unpack_from("<Q", data, p)
        p += 8
        p = off + dir_off if dir_off else p + 16 * 4
        count, = struct.unpack_from("<I", data, p)
        p += 4
    else:
        p += 16 * 4
        count, = struct.unpack_from("<I", data, p)
        p += 4
    files = []
    with open(path, "rb") as fh:
        full = fh.read()
    for _ in range(count):
        ln, = struct.unpack_from("<I", full, p)
        p += 4
        name = full[p:p + ln].rstrip(b"\0").decode("utf-8", "replace")
        p += ln
        ofs, size = struct.unpack_from("<QQ", full, p)
        p += 16 + 16
        if ver >= 2:
            p += 4
        files.append((name, size))
    return files, (ver, vmaj, vmin, vpat)


def source_of(name):
    m = re.match(r"res://\.godot/imported/(.+?)-[0-9a-f]{32}\.(\w+)$", name)
    if m:
        return m.group(1), m.group(2)
    return name.replace("res://", ""), name.rsplit(".", 1)[-1]


def main():
    argv = sys.argv[1:]
    path = argv[0] if argv else "build/web_art_hab/index.pck"
    top = int(argv[argv.index("--top") + 1]) if "--top" in argv else 40
    files, ver = read_table(path)
    total = os.path.getsize(path)
    by_src, by_kind = Counter(), Counter()
    for name, size in files:
        src, ext = source_of(name)
        by_src[src] += size
        kind = "glb" if src.endswith(".glb") else ext
        by_kind[kind] += size
    print("pack %s: %.2f MB, %d files, format %s" % (path, total / 1e6, len(files), ver))
    for k, v in by_kind.most_common():
        print("  kind %-10s %8.2f MB" % (k, v / 1e6))
    print("top sources:")
    for k, v in by_src.most_common(top):
        print("  %8.3f MB  %s" % (v / 1e6, k))
    if "--json" in argv:
        json.dump({"total": total, "by_src": dict(by_src), "by_kind": dict(by_kind)},
                  open(argv[argv.index("--json") + 1], "w"), indent=1)


main()
