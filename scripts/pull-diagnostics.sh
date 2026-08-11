#!/usr/bin/env bash
# pull-diagnostics.sh — retrieve the D-107 diagnostic traces from the connected
# iPhone over the cable, with NO user intervention. Run by Claude Code at the end
# of (or during) the observed session; the user only plays.
#
# The app writes JSON Lines traces to its Documents/LumarDiagnostics/ container.
# `devicectl` reads an installed app's appDataContainer over USB (developer mode
# on the paired device) — no Finder, no export, no file handling by the user.
#
# ⚠️ TEMPORANEO (D-107): dev tooling for the rhythm-diagnosis session.
#
# Usage:  scripts/pull-diagnostics.sh [output-dir]
set -euo pipefail

BUNDLE_ID="com.scabo.lumarlounge"
OUT="${1:-diagnostics-traces/$(date +%Y%m%d-%H%M%S)}"

# Pick the connected iPhone from devicectl: any iPhone line that is not
# "unavailable", taking its Identifier UUID (device state words vary —
# "connected" / "available" / "paired").
DEV="$(xcrun devicectl list devices 2>/dev/null \
      | grep -i 'iPhone' | grep -viE 'unavailable' \
      | grep -oiE '[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}' \
      | head -1)"
if [ -z "${DEV:-}" ]; then
  echo "No available iPhone found. Is it connected, paired, and in developer mode?" >&2
  xcrun devicectl list devices >&2 || true
  exit 1
fi
echo "device: $DEV"
mkdir -p "$OUT"

echo "pulling Documents/LumarDiagnostics → $OUT ..."
xcrun devicectl device copy from --device "$DEV" \
  --domain-type appDataContainer --domain-identifier "$BUNDLE_ID" \
  --source Documents/LumarDiagnostics --destination "$OUT" 2>&1 | tail -3

echo
echo "=== traces retrieved ==="
found=0
while IFS= read -r f; do
  found=1
  printf "  %-40s %6s records\n" "$(basename "$f")" "$(wc -l < "$f" | tr -d ' ')"
done < <(find "$OUT" -name '*.jsonl' 2>/dev/null | sort)
[ "$found" = 0 ] && echo "  (none — has the recording build been opened at least once?)"
echo "output: $OUT"
