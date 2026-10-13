#!/bin/bash
set -euo pipefail
arch=${1:?Expected x64 or arm64}
case "$arch" in x64|arm64) ;; *) exit 2 ;; esac
root=$(cd "$(dirname "$0")/../.." && pwd)
packages="$root/build/linux/$arch/packages"
mapfile -t images < <(find "$packages" -maxdepth 1 -name '*.AppImage' -type f)
test "${#images[@]}" -eq 1
cc "$root/.github/scripts/appimage_webkit_probe.c" -o "$packages/webkit-probe" \
  $(pkg-config --cflags --libs webkit2gtk-4.1)
docker build -t venera-appimage-smoke -f "$root/.github/scripts/appimage-smoke.Dockerfile" "$root/.github/scripts"
timeout 120 docker run --rm --network none \
  --mount "type=bind,source=$packages,target=/packages,readonly" \
  --mount "type=bind,source=$root/.github/scripts,target=/scripts,readonly" \
  venera-appimage-smoke bash /scripts/smoke_appimage.sh \
  "/packages/$(basename "${images[0]}")" /packages/webkit-probe
# Allow nested namespaces in Docker, then explicitly enable WebKit's own
# sandbox. This catches missing bubblewrap/dbus-proxy files and sandbox mounts.
timeout 120 docker run --rm --network none --security-opt seccomp=unconfined \
  --security-opt apparmor=unconfined \
  --security-opt systempaths=unconfined \
  -e VENERA_SMOKE_SANDBOX=1 \
  --mount "type=bind,source=$packages,target=/packages,readonly" \
  --mount "type=bind,source=$root/.github/scripts,target=/scripts,readonly" \
  venera-appimage-smoke bash /scripts/smoke_appimage.sh \
  "/packages/$(basename "${images[0]}")" /packages/webkit-probe
