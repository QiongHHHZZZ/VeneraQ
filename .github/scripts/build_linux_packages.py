#!/usr/bin/env python3
"""Package an existing Flutter Linux bundle as RPM and AppImage (no rebuild)."""

import argparse
import hashlib
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import urllib.request
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
from appimage_runtime import collect_runtime, validate_runtime

ROOT = Path(__file__).resolve().parents[2]
ARCHES = {"x64": ("x86_64", 62), "arm64": ("aarch64", 183)}
TOOLS = {
    "x64": (
        "ed4ce84f0d9caff66f50bcca6ff6f35aae54ce8135408b3fa33abfc3cb384eb0",
        "2fca8b443c92510f1483a883f60061ad09b46b978b2631c807cd873a47ec260d",
    ),
    "arm64": (
        "f0837e7448a0c1e4e650a93bb3e85802546e60654ef287576f46c71c126a9158",
        "00cbdfcf917cc6c0ff6d3347d59e0ca1f7f45a6df1a428a0d6d8a78664d87444",
    ),
}


def run(*args, **kwargs):
    subprocess.run([str(arg) for arg in args], check=True, **kwargs)


def versions(value):
    if not re.fullmatch(r"\d+\.\d+\.\d+(?:-[A-Za-z0-9.]+)?(?:\+\d+)?", value):
        raise ValueError(f"Unsupported package version: {value}")
    version, _, build = value.partition("+")
    return version.replace("-", "~", 1), build or "1"


def validate_bundle(bundle, arch):
    binary = bundle / "venera-next"
    with binary.open("rb") as stream:
        header = stream.read(20)
    if (len(header) != 20 or header[:6] != b"\x7fELF\x02\x01"
            or int.from_bytes(header[18:20], "little") != ARCHES[arch][1]):
        raise ValueError(f"{binary} is not a Linux {arch} ELF binary")
    for item in ("lib/libflutter_linux_gtk.so", "data/icudtl.dat", "data/flutter_assets"):
        if not (bundle / item).exists():
            raise ValueError(f"Incomplete Flutter bundle: missing {item}")


def desktop_file(exec_path):
    return f"""[Desktop Entry]
Type=Application
Name=VeneraNext
Comment=Comic reader
Exec={exec_path} %U
Icon=venera-next
Terminal=false
Categories=Graphics;Viewer;
MimeType=x-scheme-handler/venera;
"""


def stage_bundle(bundle, destination):
    shutil.copytree(bundle, destination, symlinks=True)
    (destination / "venera-next").chmod(0o755)
    shutil.copyfile(ROOT / "LICENSE", destination / "LICENSE")


def rpm_spec(version, build, private_libs):
    # Private Flutter/plugin libraries must not become global RPM provides, nor
    # requirements on a nonexistent system package. Keep system ELF requirements.
    excluded = "|".join(re.escape(name) for name in sorted(private_libs))
    return f"""%global __provides_exclude_from ^/opt/venera-next/.*$
%global __requires_exclude ^({excluded})(\\(.*\\))?$
%global _build_id_links none
%global __os_install_post %{{nil}}
Name: venera-next
Version: {version}
Release: {build}
Summary: VeneraNext comic reader
License: GPL-3.0-only
URL: https://github.com/CyrilPeng/venera-next
Requires: gtk3, webkit2gtk4.1

%description
A cross-platform comic reader with JavaScript source extensions and local reading.

%install
mkdir -p "%{{buildroot}}/opt" "%{{buildroot}}/usr/bin" "%{{buildroot}}/usr/share/applications" "%{{buildroot}}/usr/share/icons/hicolor/256x256/apps"
cp -a "%{{_sourcedir}}/app" "%{{buildroot}}/opt/venera-next"
ln -s /opt/venera-next/venera-next "%{{buildroot}}/usr/bin/venera-next"
install -m644 "%{{_sourcedir}}/venera-next.desktop" "%{{buildroot}}/usr/share/applications/"
install -m644 "%{{_sourcedir}}/venera-next.png" "%{{buildroot}}/usr/share/icons/hicolor/256x256/apps/"

%files
/opt/venera-next
/usr/bin/venera-next
/usr/share/applications/venera-next.desktop
/usr/share/icons/hicolor/256x256/apps/venera-next.png
"""


def build_rpm(bundle, out, arch, version, work):
    top = work / "rpm"
    sources = top / "SOURCES"
    sources.mkdir(parents=True)
    (top / "SPECS").mkdir()
    stage_bundle(bundle, sources / "app")
    (sources / "venera-next.desktop").write_text(desktop_file("venera-next"), encoding="utf-8")
    shutil.copyfile(ROOT / "assets/app_icon.png", sources / "venera-next.png")
    libs = {p.name for p in (bundle / "lib").rglob("*.so*")}
    spec = top / "SPECS/venera-next.spec"
    spec.write_text(rpm_spec(*versions(version), libs), encoding="utf-8")
    run("rpmbuild", "--define", f"_topdir {top}", "--target", ARCHES[arch][0], "-bb", spec)
    packages = list((top / "RPMS").rglob("*.rpm"))
    if len(packages) != 1 or packages[0].stat().st_size == 0:
        raise RuntimeError("Expected exactly one nonempty RPM")
    package = out / packages[0].name
    shutil.copyfile(packages[0], package)
    run("rpm", "-qip", package)
    run("rpm", "-qlp", package)


def download_verified(url, path, digest):
    if not path.exists():
        with urllib.request.urlopen(url, timeout=120) as response, path.open("wb") as target:
            shutil.copyfileobj(response, target)
    if hashlib.sha256(path.read_bytes()).hexdigest() != digest:
        path.unlink()
        raise RuntimeError(f"SHA256 mismatch: {url}")
    path.chmod(0o755)


def stage_appdir(bundle, appdir):
    stage_bundle(bundle, appdir / "usr/lib/venera-next")
    (appdir / "venera-next.desktop").write_text(desktop_file("AppRun"), encoding="utf-8")
    shutil.copyfile(ROOT / "assets/app_icon.png", appdir / "venera-next.png")
    shutil.copyfile(ROOT / "assets/app_icon.png", appdir / ".DirIcon")
    apprun = appdir / "AppRun"
    apprun.write_text('''#!/bin/sh
set -eu
APPDIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
. "$APPDIR/runtime-env.sh"
"$APPDIR/usr/lib/venera-next/venera-next" "$@"
''', encoding="utf-8", newline="\n")
    apprun.chmod(0o755)


def build_appimage(bundle, out, arch, version, work):
    appdir = work / "VeneraNext.AppDir"
    stage_appdir(bundle, appdir)
    collect_runtime(appdir)
    cache = out / "tools"
    cache.mkdir(exist_ok=True)
    machine = ARCHES[arch][0]
    tool = cache / f"appimagetool-1.9.1-{machine}.AppImage"
    runtime = cache / f"runtime-20251108-{machine}"
    download_verified(
        f"https://github.com/AppImage/appimagetool/releases/download/1.9.1/appimagetool-{machine}.AppImage",
        tool, TOOLS[arch][0],
    )
    download_verified(
        f"https://github.com/AppImage/type2-runtime/releases/download/20251108/runtime-{machine}",
        runtime, TOOLS[arch][1],
    )
    # Extract the build tool so CI does not need FUSE or a privileged container.
    run(tool, "--appimage-extract", cwd=work, stdout=subprocess.DEVNULL)
    package = out / f"VeneraNext-{version}-{machine}.AppImage"
    run(work / "squashfs-root/AppRun", "--no-appstream", "--runtime-file", runtime,
        appdir, package, env={**os.environ, "ARCH": machine, "SOURCE_DATE_EPOCH": os.environ.get("SOURCE_DATE_EPOCH", "0")})
    if not package.exists() or package.stat().st_size == 0:
        raise RuntimeError("AppImage was not produced")
    package.chmod(0o755)
    # Validate the produced image, including the entry point and Flutter assets.
    extracted = work / "verify"
    extracted.mkdir()
    run(package, "--appimage-extract", cwd=extracted, stdout=subprocess.DEVNULL)
    validate_bundle(extracted / "squashfs-root/usr/lib/venera-next", arch)
    validate_runtime(extracted / "squashfs-root")
    if not os.access(extracted / "squashfs-root/AppRun", os.X_OK):
        raise RuntimeError("AppImage entry point is not executable")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--arch", required=True, choices=ARCHES)
    parser.add_argument("--bundle", type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--format", choices=("rpm", "appimage", "all"), default="all")
    args = parser.parse_args()
    bundle = (args.bundle or ROOT / f"build/linux/{args.arch}/release/bundle").resolve()
    out = (args.output or ROOT / f"build/linux/{args.arch}/packages").resolve()
    validate_bundle(bundle, args.arch)
    version = re.search(r"^version:\s*(\S+)", (ROOT / "pubspec.yaml").read_text(), re.M).group(1)
    versions(version)
    out.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="packaging-", dir=out) as temp:
        work = Path(temp)
        if args.format in ("rpm", "all"):
            build_rpm(bundle, out, args.arch, version, work)
        if args.format in ("appimage", "all"):
            build_appimage(bundle, out, args.arch, version, work)


if __name__ == "__main__":
    main()
