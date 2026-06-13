"""Build the distribution zips in godot/export/ from the raw Godot exports.

Usage: python package_dist.py  (run from anywhere)

The macOS zip must be rebuilt entry-by-entry from Godot's own zip, with each
entry marked as Unix-created (create_system=3). macOS only restores the
executable permission bits when the entry claims a Unix origin; a zip made by
Windows tools extracts with no +x bit and the app fails with
"the application can't be opened".
"""

import os
import zipfile

GODOT_DIR = os.path.dirname(os.path.abspath(__file__))
EXPORT = os.path.join(GODOT_DIR, "export")
HOW_TO_PLAY = os.path.join(GODOT_DIR, "HOW_TO_PLAY.txt")


def add_text_file(zout, path, arcname):
    info = zipfile.ZipInfo(arcname)
    info.create_system = 3
    info.external_attr = 0o644 << 16
    info.compress_type = zipfile.ZIP_DEFLATED
    with open(path, "rb") as f:
        zout.writestr(info, f.read())


def build_macos():
    src = os.path.join(EXPORT, "macos", "Slippington.zip")
    dst = os.path.join(EXPORT, "Slippington-macOS.zip")
    with zipfile.ZipFile(src) as zin, zipfile.ZipFile(
        dst, "w", zipfile.ZIP_DEFLATED
    ) as zout:
        for info in zin.infolist():
            data = zin.read(info.filename)
            out = zipfile.ZipInfo(info.filename, date_time=info.date_time)
            out.create_system = 3
            out.external_attr = info.external_attr
            out.compress_type = zipfile.ZIP_DEFLATED
            zout.writestr(out, data)
        add_text_file(zout, HOW_TO_PLAY, "HOW_TO_PLAY.txt")
    print("wrote", dst)


def build_windows():
    src = os.path.join(EXPORT, "windows")
    dst = os.path.join(EXPORT, "Slippington-Windows.zip")
    with zipfile.ZipFile(dst, "w", zipfile.ZIP_DEFLATED) as zout:
        for name in sorted(os.listdir(src)):
            if name.endswith(".TMP") or "~" in name:
                continue
            zout.write(os.path.join(src, name), name)
        add_text_file(zout, HOW_TO_PLAY, "HOW_TO_PLAY.txt")
    print("wrote", dst)


def build_web():
    # The web export is a directory of static files (index.html, .wasm, .pck,
    # .js, ...) meant to be deployed to a static host. Bundle it into a zip for
    # handoff; skip cleanly if the Web preset hasn't been exported yet.
    src = os.path.join(EXPORT, "web")
    if not os.path.isdir(src):
        print("skip web: no export/web/ (export the Web preset first)")
        return
    dst = os.path.join(EXPORT, "Slippington-Web.zip")
    with zipfile.ZipFile(dst, "w", zipfile.ZIP_DEFLATED) as zout:
        for root, _dirs, files in os.walk(src):
            for name in sorted(files):
                full = os.path.join(root, name)
                zout.write(full, os.path.relpath(full, src))
        add_text_file(zout, HOW_TO_PLAY, "HOW_TO_PLAY.txt")
    print("wrote", dst)


if __name__ == "__main__":
    build_macos()
    build_windows()
    build_web()
