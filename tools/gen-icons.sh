#!/bin/bash
# Regenerate the Le Détourage app-icon master and all idiom sizes.
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
OUT="$DIR/../Sources/Resources/Assets.xcassets/AppIcon.appiconset"

MASTER="$OUT/icon-1024.png"
swift "$DIR/make-icon.swift" "$MASTER"

sizes=(16 32 128 256 512)
for s in "${sizes[@]}"; do
  s2=$((s * 2))
  sips -z "$s" "$s" "$MASTER" --out "$OUT/mac-$s.png" >/dev/null
  sips -z "$s2" "$s2" "$MASTER" --out "$OUT/mac-$s@2x.png" >/dev/null
done
echo "icons generated in $OUT"
