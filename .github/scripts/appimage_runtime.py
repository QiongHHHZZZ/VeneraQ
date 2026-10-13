"""Collect the Ubuntu runtime for a relocatable GTK/WebKit AppDir.

glibc and graphics drivers remain host interfaces. Everything else in the ELF
dependency closure must resolve inside the image. Run only on trusted build files.
"""

import os
from pathlib import Path
import re
import shutil
import subprocess


RUNTIME_PACKAGES = (
    "libwebkit2gtk-4.1-0", "libjavascriptcoregtk-4.1-0", "libgtk-3-0",
    "libgtk-3-common", "libgdk-pixbuf-2.0-0", "libgdk-pixbuf2.0-bin", "librsvg2-common",
    "libgstreamer1.0-0",
    "glib-networking", "gstreamer1.0-plugins-base", "gstreamer1.0-plugins-good",
    "gsettings-desktop-schemas", "shared-mime-info", "adwaita-icon-theme",
    "fontconfig-config",
    "bubblewrap", "xdg-dbus-proxy",
)
HOST_LIBRARIES = re.compile(
    r"^(?:ld-linux[^/]*|lib(?:c|m|pthread|dl|rt|resolv|util|anl|nss_[^.]+)\.so\..*|"
    r"lib(?:GL|EGL|GLX|GLdispatch|OpenGL|GLESv[12]|gbm|drm[^.]*|vulkan)\.so\..*)$"
)


def output(*args, **kwargs):
    return subprocess.check_output(args, text=True, **kwargs)


def is_elf(path):
    if not path.is_file():
        return False
    with path.open("rb") as stream:
        return stream.read(4) == b"\x7fELF"


def parse_ldd(text):
    if "=> not found" in text:
        raise RuntimeError(f"Unresolved AppImage dependency:\n{text}")
    return [Path(match.group(1)) for match in re.finditer(
        r"(?:=>\s+|^\s*)(/[^\n]+?)\s+\(0x", text, re.M
    )]


def dependencies(path, library_path):
    result = subprocess.run(
        ["ldd", str(path)], text=True, capture_output=True,
        env={**os.environ, "LC_ALL": "C", "LD_LIBRARY_PATH": library_path},
    )
    if result.returncode:
        raise RuntimeError(f"Cannot inspect {path}: {result.stdout}{result.stderr}")
    return parse_ldd(result.stdout)


def copy_file(source, destination):
    destination.parent.mkdir(parents=True, exist_ok=True)
    # Dereference system links: an absolute link would escape the AppDir.
    shutil.copy2(source, destination)


def owning_package(source):
    # ldconfig may report /lib aliases on merged-/usr hosts while dpkg records
    # the package's /usr/lib path (or the other way around).
    candidates = [source, source.resolve()]
    for path in list(candidates):
        name = str(path)
        if name.startswith("/usr/lib/"):
            candidates.append(Path(name.removeprefix("/usr")))
        elif name.startswith("/lib/"):
            candidates.append(Path("/usr" + name))
    for path in dict.fromkeys(candidates):
        result = subprocess.run(["dpkg-query", "-S", str(path)], text=True, capture_output=True)
        if result.returncode == 0:
            return result.stdout.splitlines()[0].split(": ", 1)[0]
    raise RuntimeError(f"Cannot identify dependency package for {source}")


def collect_runtime(appdir):
    appdir = appdir.resolve()
    lib = appdir / "usr/lib"
    packages = set(RUNTIME_PACKAGES)
    for package in RUNTIME_PACKAGES:
        for name in output("dpkg-query", "-L", package).splitlines():
            source = Path(name)
            if not source.is_file() or not name.startswith(("/usr/lib/", "/usr/share/", "/etc/fonts/", "/usr/bin/")):
                continue
            if name.startswith(("/usr/share/doc/", "/usr/share/man/", "/usr/share/locale/")):
                continue
            # WebKit binds LD_LIBRARY_PATH into its child sandbox. Keep font
            # configuration underneath that prefix so it remains visible there.
            destination = (lib / "fontconfig" / name.removeprefix("/etc/fonts/")) if name.startswith("/etc/fonts/") else appdir / name.lstrip("/")
            copy_file(source, destination)

    subprocess.run([
        "cc", "-O2", "-Wall", "-Wextra", "-Werror",
        str(Path(__file__).with_name("appimage_relocate.c")),
        "-o", str(appdir / "usr/bin/venera-relocate-webkit"),
    ], check=True)
    library_path = f"{lib / 'venera-next/lib'}:{lib}"
    pending = [p for p in appdir.rglob("*") if is_elf(p)]
    inspected = set()
    while pending:
        binary = pending.pop()
        if binary in inspected:
            continue
        inspected.add(binary)
        for source in dependencies(binary, library_path):
            if source.is_relative_to(appdir) or HOST_LIBRARIES.fullmatch(source.name):
                continue
            destination = lib / source.name
            if not destination.exists():
                copy_file(source, destination)
                pending.append(destination)
                # Preserve redistribution notices for every dependency package.
                packages.add(owning_package(source))

    notices = appdir / "usr/share/doc/venera-next-runtime"
    for package in sorted(packages):
        copyright_file = Path("/usr/share/doc") / package.split(":")[0] / "copyright"
        if not copyright_file.is_file():
            raise RuntimeError(f"Missing copyright notice for {package}")
        copy_file(copyright_file, notices / (package.replace(":", "_") + ".copyright"))
    (notices / "packages.txt").write_text(
        output("dpkg-query", "-W", "-f=${Package}\t${Version}\n", *sorted(packages)),
        encoding="utf-8",
    )

    webkit = list(lib.glob("*/webkit2gtk-4.1"))
    pixbuf = list(lib.glob("*/gdk-pixbuf-2.0/2.10.0"))
    gio = list(lib.glob("*/gio/modules"))
    gst = list(lib.glob("*/gstreamer-1.0"))
    if not (len(webkit) == len(pixbuf) == len(gio) == len(gst) == 1):
        raise RuntimeError("Missing or ambiguous WebKit/GTK runtime directories")
    for helper in ("WebKitWebProcess", "WebKitNetworkProcess"):
        if not (webkit[0] / helper).is_file():
            raise RuntimeError(f"Missing WebKit helper: {helper}")
    query = list(lib.glob("*/gdk-pixbuf-2.0/gdk-pixbuf-query-loaders"))
    if len(query) != 1:
        raise RuntimeError("Missing gdk-pixbuf-query-loaders")
    # Cache uses a placeholder expanded at launch, never build-machine paths.
    cache = output(str(query[0]), *map(str, pixbuf[0].glob("loaders/*.so")),
                   env={**os.environ, "LD_LIBRARY_PATH": library_path})
    (pixbuf[0] / "loaders.cache.in").write_text(cache.replace(str(appdir), "@APPDIR@"))
    subprocess.run(["glib-compile-schemas", str(appdir / "usr/share/glib-2.0/schemas")], check=True)
    triplet = webkit[0].parent.name
    (appdir / "runtime-env.sh").write_text(runtime_environment(triplet), encoding="utf-8")
    validate_runtime(appdir)


def validate_runtime(appdir):
    appdir = appdir.resolve()
    lib = appdir / "usr/lib"
    for binary in (p for p in appdir.rglob("*") if is_elf(p)):
        for dependency in dependencies(binary, f"{lib / 'venera-next/lib'}:{lib}"):
            if not dependency.is_relative_to(appdir) and not HOST_LIBRARIES.fullmatch(dependency.name):
                raise RuntimeError(f"{binary} still requires host library {dependency}")


def runtime_environment(triplet):
    return '''# Sourced by AppRun; APPDIR is the extracted or mounted image root.
export LD_LIBRARY_PATH="$APPDIR/usr/lib/venera-next/lib:$APPDIR/usr/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export WEBKIT_INJECTED_BUNDLE_PATH="$APPDIR/usr/lib/TRIPLET/webkit2gtk-4.1/injected-bundle"
export XDG_DATA_DIRS="$APPDIR/usr/share:${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
export GSETTINGS_SCHEMA_DIR="$APPDIR/usr/share/glib-2.0/schemas"
export FONTCONFIG_PATH="$APPDIR/usr/lib/fontconfig"
export FONTCONFIG_FILE="$APPDIR/usr/lib/fontconfig/fonts.conf"
export GIO_MODULE_DIR="$APPDIR/usr/lib/TRIPLET/gio/modules"
export GST_PLUGIN_SYSTEM_PATH_1_0="$APPDIR/usr/lib/TRIPLET/gstreamer-1.0"
export GST_PLUGIN_SCANNER="$APPDIR/usr/lib/TRIPLET/gstreamer1.0/gstreamer-1.0/gst-plugin-scanner"
export GDK_PIXBUF_MODULEDIR="$APPDIR/usr/lib/TRIPLET/gdk-pixbuf-2.0/2.10.0/loaders"
# Each mount has a different path. AppRun removes this private cache on exit.
pixbuf_cache=$(mktemp "${TMPDIR:-/tmp}/venera-pixbuf.XXXXXX")
escaped_appdir=$(printf '%s' "$APPDIR" | sed 's/[\\\\&|]/\\\\&/g')
sed "s|@APPDIR@|$escaped_appdir|g" "$GDK_PIXBUF_MODULEDIR/../loaders.cache.in" > "$pixbuf_cache"
export GDK_PIXBUF_MODULE_FILE="$pixbuf_cache"
# Keep helper paths short enough for in-place ELF string relocation. This private
# directory is also exposed to WebKit's sandbox through LD_LIBRARY_PATH.
webkit_runtime=$(mktemp -d /tmp/vXXXXXX)
trap 'rm -f "$pixbuf_cache"; rm -rf "$webkit_runtime"' EXIT
ln -s "$APPDIR/usr/lib/TRIPLET/webkit2gtk-4.1" "$webkit_runtime/w"
cp "$APPDIR/usr/bin/bwrap" "$webkit_runtime/b"
cp "$APPDIR/usr/bin/xdg-dbus-proxy" "$webkit_runtime/d"
"$APPDIR/usr/bin/venera-relocate-webkit" "$APPDIR/usr/lib/libwebkit2gtk-4.1.so.0" \\
  "$webkit_runtime/libwebkit2gtk-4.1.so.0" /usr/lib/TRIPLET/webkit2gtk-4.1 "$webkit_runtime"
export LD_LIBRARY_PATH="$webkit_runtime:$LD_LIBRARY_PATH"
'''.replace("TRIPLET", triplet)
