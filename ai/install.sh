#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

# CFBundleVersion is $(CURRENT_PROJECT_VERSION). Without this file the key is omitted from the
# built Info.plist and App.version force-unwraps nil at launch.
xcconfig="config/local.xcconfig"
if [[ ! -f "$xcconfig" ]] || ! grep -q '^CURRENT_PROJECT_VERSION[[:space:]]*=' "$xcconfig"; then
  printf 'CURRENT_PROJECT_VERSION = 0.0.0\n' >> "$xcconfig"
fi

if ! security find-identity -v -p codesigning | grep -q "Local Self-Signed"; then
  scripts/codesign/setup_local.sh
fi

ai/build.sh

app="$PWD/DerivedData/Build/Products/Debug/AltTab.app"
dest="/Applications/AltTab.app"
# The installed binary and its frameworks stay mapped while the process lives. Replacing files
# inside the existing bundle also fails on a notarized copy (Operation not permitted). Quit, then
# remove the whole bundle before copying.
osascript -e 'tell application "AltTab" to quit' >/dev/null 2>&1 || true
for _ in 1 2 3 4 5 6 7 8 9 10; do
  pgrep -f "$dest/Contents/MacOS/AltTab" >/dev/null || break
  sleep 0.3
done
if pgrep -f "$dest/Contents/MacOS/AltTab" >/dev/null; then
  pkill -f "$dest/Contents/MacOS/AltTab" || true
  sleep 0.5
fi
rm -rf "$dest"
ditto "$app" "$dest"
echo "Installed $dest"
open -n "$dest"
