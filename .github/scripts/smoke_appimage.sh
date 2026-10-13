#!/bin/bash
set -euo pipefail
# Run inside appimage-smoke.Dockerfile, with packages and this script mounted RO.
if ldconfig -p | grep -E 'libgtk-3\.so|libwebkit2gtk-4\.1' >/dev/null; then
  echo 'Smoke image unexpectedly contains GTK/WebKit' >&2
  exit 1
fi
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cd "$work"
"$1" --appimage-extract >/dev/null
export APPDIR="$work/squashfs-root"
export LIBGL_ALWAYS_SOFTWARE=1
export GDK_BACKEND=x11
# Docker's namespace policy prevents WebKit's nested sandbox. This applies only
# to this test process; the distributed AppRun never disables the sandbox.
if [ "${VENERA_SMOKE_SANDBOX:-0}" != 1 ]; then
  export WEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS=1
fi
export PROBE="$2"
dbus-run-session -- xvfb-run -a bash -euo pipefail <<'SMOKE'
  (
    . "$APPDIR/runtime-env.sh"
    timeout 50 "$PROBE"
  ) 2>&1 | tee webkit.log
  if grep -E 'Fontconfig error|error while loading shared libraries|symbol lookup error' webkit.log; then
    exit 1
  fi
  "$APPDIR/AppRun" >app.log 2>&1 &
  app_pid=$!
  trap 'kill "$app_pid" 2>/dev/null || true; cat app.log' EXIT
  found=false
  for attempt in $(seq 1 30); do
    if ! kill -0 "$app_pid" 2>/dev/null; then
      echo 'AppImage exited before showing a window' >&2
      exit 1
    fi
    if xdotool search --onlyvisible --name '^VeneraNext$' >/dev/null 2>&1; then
      found=true
      break
    fi
    sleep 1
  done
  test "$found" = true
  sleep 5
  kill -0 "$app_pid"
  if grep -E 'error while loading shared libraries|symbol lookup error' app.log; then
    exit 1
  fi
SMOKE
