#!/usr/bin/env bash
# Build the C++ plugin, install it system-wide (Qt5 QML imports), upgrade the
# plasmoid package, and restart plasmashell. Run from any cwd.
set -euo pipefail

cd "$(dirname "$0")"
BUILD=build
PKG=package

mkdir -p "$BUILD"
(cd "$BUILD" && cmake -DCMAKE_BUILD_TYPE=Release .. >/dev/null)
(cd "$BUILD" && make -j"$(nproc)")

echo ":: installing QML plugin (sudo)"
sudo make -C "$BUILD" install

echo ":: upgrading plasmoid package"
kpackagetool5 --type Plasma/Applet --upgrade "$PKG" \
    || kpackagetool5 --type Plasma/Applet --install "$PKG"

echo ":: restarting plasmashell"
# Bounded kquit: if plasmashell is already hung, DBus reply never arrives; fall back to SIGKILL.
if ! timeout 3 kquitapp5 plasmashell >/dev/null 2>&1; then
    echo ":: kquitapp5 timed out — forcing kill"
    pkill -9 plasmashell 2>/dev/null || true
fi
# Wait briefly for the process to actually exit.
for i in 1 2 3 4 5; do
    pgrep -x plasmashell >/dev/null || break
    sleep 0.2
done
# Fully detach the new plasmashell: new session, null stdin, nohup, background, disown.
setsid nohup kstart5 plasmashell </dev/null >/tmp/plasmashell.log 2>&1 &
disown 2>/dev/null || true

echo ":: done. tail -f /tmp/plasmashell.log for errors."
