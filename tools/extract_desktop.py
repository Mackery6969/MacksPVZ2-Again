#!/usr/bin/env python3
"""Unpack a PVZGE desktop build (Windows .exe) into a plain web build tree.

The desktop releases (pre-releases on github.com/Gzh0821/pvzg_site) are Tauri 2
apps: the whole Cocos build is compiled into the exe as a phf map of
(&str path, &[u8] brotli data) entries. Each entry is four u64s in the image -
path_ptr, path_len, data_ptr, data_len - so we scan every section for that
shape and keep the ones whose path is a printable "/file.ext".

The output has the same layout as the Docker image's /usr/share/nginx/html, so
the other tools can point at <out>/assets/resources/... directly. The desktop
build is usually newer than the image, and also carries the mod loader the web
build lacks (assets/gp-next-*.js, mod-api-*.js, js-mod-loader-*.js, ...).

Needs: pip install pefile brotli
Usage: python3 tools/extract_desktop.py pvzge.exe <out dir>
"""
import os, struct, sys

import brotli, pefile


def section_map(pe):
    """(va, size, file offset) for each section, to turn pointers into offsets."""
    base = pe.OPTIONAL_HEADER.ImageBase
    return [(base + s.VirtualAddress, min(s.Misc_VirtualSize, s.SizeOfRawData), s.PointerToRawData)
            for s in pe.sections]


def va_to_offset(sections, va):
    for start, size, raw in sections:
        if start <= va < start + size:
            return raw + va - start
    return None


def find_assets(pe, image):
    """Scan for (path_ptr, path_len, data_ptr, data_len) entries; return {path: (offset, len)}."""
    sections = section_map(pe)
    assets = {}
    for s in pe.sections:
        body = image[s.PointerToRawData:s.PointerToRawData + s.SizeOfRawData]
        for i in range(0, len(body) - 32, 8):
            path_ptr, path_len, data_ptr, data_len = struct.unpack_from("<4Q", body, i)
            if not (1 < path_len < 300 and 0 < data_len < 1 << 31):
                continue
            path_at = va_to_offset(sections, path_ptr)
            data_at = va_to_offset(sections, data_ptr)
            if path_at is None or data_at is None or data_at + data_len > len(image):
                continue
            path = image[path_at:path_at + path_len]
            # Real asset keys are absolute file paths with an extension; this
            # rejects the pointer-shaped noise elsewhere in the image.
            if path[:1] != b"/" or b"." not in path or not all(32 <= c < 127 for c in path):
                continue
            assets[path.decode()] = (data_at, data_len)
    return assets


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    exe, outdir = sys.argv[1], sys.argv[2]
    image = open(exe, "rb").read()
    assets = find_assets(pefile.PE(exe, fast_load=True), image)

    raw_count = 0
    for path, (at, length) in sorted(assets.items()):
        blob = image[at:at + length]
        try:
            blob = brotli.decompress(blob)
        except brotli.error:
            # Not every Tauri asset is guaranteed compressed; write it through as-is.
            raw_count += 1
        dest = os.path.join(outdir, path.lstrip("/"))
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        with open(dest, "wb") as fh:
            fh.write(blob)
    print(f"  {len(assets)} files -> {outdir} ({raw_count} stored uncompressed)")


if __name__ == "__main__":
    main()
