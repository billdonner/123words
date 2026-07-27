#!/usr/bin/env bash
# Capture App Store screenshots from both sims.
# Sets UserDefaults to drive the app to a target home page, game, or race
# state, launches, and screenshots. Race shots use the screenshotRace*
# hooks in RaceView/RaceSession to freeze a compelling preset.
set -euo pipefail

BUNDLE=com.123words.app
IPHONE=C816FD4C-5914-4170-8A4A-C432D0C73CEC   # iPhone 16 Pro Max (6.9", 1320x2868)
IPAD=F4AA8422-290E-4C7D-8D07-DA15769AC23F     # iPad Pro 13" (2064x2752)

OUT_IPHONE=AppStore/Screenshots/iPhone
OUT_IPAD=AppStore/Screenshots/iPad

# All keys we ever poke; cleared before each shot so state is hermetic.
SCRATCH_KEYS=(
  screenshotShowVoicePicker screenshotShowSettings screenshotShowGallery
  screenshotWord screenshotHomePage screenshotLaunchGame
  screenshotStartRace screenshotRaceDuration screenshotRaceTab
  screenshotRaceScore screenshotRaceRemaining screenshotRaceFinished
)

# capture <device> <output> -- then any number of "key=value:type" pairs.
# type ∈ string,bool,int,float. Example: "screenshotStartRace=true:bool".
capture() {
  local dev=$1 out=$2
  shift 2

  xcrun simctl terminate "$dev" "$BUNDLE" 2>/dev/null || true
  for k in "${SCRATCH_KEYS[@]}"; do
    xcrun simctl spawn "$dev" defaults delete "$BUNDLE" "$k" 2>/dev/null || true
  done
  xcrun simctl spawn "$dev" defaults write "$BUNDLE" hasSeenParentOnboarding -bool true

  for pair in "$@"; do
    local kv=${pair%%:*}
    local typ=${pair##*:}
    local k=${kv%%=*}
    local v=${kv#*=}
    case "$typ" in
      bool)   xcrun simctl spawn "$dev" defaults write "$BUNDLE" "$k" -bool "$v" ;;
      int)    xcrun simctl spawn "$dev" defaults write "$BUNDLE" "$k" -int "$v" ;;
      float)  xcrun simctl spawn "$dev" defaults write "$BUNDLE" "$k" -float "$v" ;;
      *)      xcrun simctl spawn "$dev" defaults write "$BUNDLE" "$k" -string "$v" ;;
    esac
  done

  xcrun simctl launch "$dev" "$BUNDLE" >/dev/null
  sleep 5
  xcrun simctl io "$dev" screenshot "$out"
  echo "  ✓ $(basename "$out") ($(file "$out" | grep -oE '[0-9]+ x [0-9]+'))"
}

shoot_set() {
  local dev=$1 outdir=$2 size=$3
  mkdir -p "$outdir"
  rm -f "$outdir"/0*.png

  # 1. Home hub — the new Race-mode landing page (Practice + Race! cards).
  capture "$dev" "$outdir/01-home-race.png"

  # 2. Race in progress — Listen & Pick mid-game, healthy timer + good score.
  capture "$dev" "$outdir/02-race-quiz.png" \
    "screenshotStartRace=true:bool" \
    "screenshotRaceTab=quiz:string" \
    "screenshotRaceScore=12:int" \
    "screenshotRaceRemaining=38:float"

  # 3. Race — Count It. Always shows a math equation on first round
  # (Memory Match starts face-down and reads as empty in a screenshot).
  capture "$dev" "$outdir/03-race-count.png" \
    "screenshotStartRace=true:bool" \
    "screenshotRaceTab=count:string" \
    "screenshotRaceScore=8:int" \
    "screenshotRaceRemaining=26:float"

  # 4. Race — Spell It under the clock.
  capture "$dev" "$outdir/04-race-spell.png" \
    "screenshotStartRace=true:bool" \
    "screenshotRaceTab=spell:string" \
    "screenshotRaceScore=16:int" \
    "screenshotRaceRemaining=18:float"

  # 5. End-of-race results overlay — score + stars + per-game breakdown.
  capture "$dev" "$outdir/05-race-results.png" \
    "screenshotStartRace=true:bool" \
    "screenshotRaceTab=quiz:string" \
    "screenshotRaceScore=24:int" \
    "screenshotRaceRemaining=0:float" \
    "screenshotRaceFinished=true:bool"

  # 6. Practice — the reader, where kids learn without a clock.
  capture "$dev" "$outdir/06-practice-reader.png" \
    "screenshotHomePage=read:string" \
    "screenshotLaunchGame=read:string" \
    "screenshotWord=fox:string"

  if [[ -n "$size" ]]; then
    local w=${size%x*} h=${size#*x}
    echo "  resizing to ${w}x${h}..."
    for f in "$outdir"/0*.png; do
      sips -z "$h" "$w" "$f" --out "$f" >/dev/null
    done
  fi
}

echo "== iPhone (1320x2868 -> 1290x2796) =="
shoot_set "$IPHONE" "$OUT_IPHONE" "1290x2796"

echo "== iPad (2064x2752) =="
shoot_set "$IPAD" "$OUT_IPAD" ""

echo ""
echo "== Final sizes =="
for f in "$OUT_IPHONE"/0*.png "$OUT_IPAD"/0*.png; do
  echo "$f: $(file "$f" | grep -oE '[0-9]+ x [0-9]+')"
done
