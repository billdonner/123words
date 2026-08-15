#!/usr/bin/env bash
# Deterministic App Store capture set for the 1.12 UI refresh.
#
# Writes only to marketing/screenshots/2026-08-15-16/raw. It never changes
# the published AppStore/Screenshots baseline or anything in App Store Connect.
set -euo pipefail

BUNDLE_ID="com.123words.app"
IPHONE_ID="${IPHONE_ID:-E77E7A03-DE6A-427E-93EC-00888401EB30}"
IPAD_ID="${IPAD_ID:-297C0281-105B-492C-BA4F-38AE8E79BFDA}"
DERIVED_DATA="${CAPTURE_DERIVED_DATA:-/private/tmp/123words-screenshot-derived}"
OUTPUT_ROOT="${CAPTURE_OUTPUT_ROOT:-marketing/screenshots/2026-08-15-16/raw}"
APP_PATH="$DERIVED_DATA/Build/Products/Release-iphonesimulator/123words.app"

SCREENSHOT_KEYS=(
  screenshotShowVoicePicker screenshotShowSettings screenshotShowGallery
  screenshotShowStickers screenshotWord screenshotHomePage screenshotLaunchGame
  screenshotStartRace screenshotRaceDuration screenshotRaceTab
  screenshotRaceScore screenshotRaceRemaining screenshotRaceFinished
  screenshotColorIndex screenshotGameWord screenshotGameWords
  screenshotQuizAnswer screenshotSpellTypedCount
)

write_default() {
  local device="$1" key="$2" value="$3" type="$4"
  case "$type" in
    bool) xcrun simctl spawn "$device" defaults write "$BUNDLE_ID" "$key" -bool "$value" ;;
    int) xcrun simctl spawn "$device" defaults write "$BUNDLE_ID" "$key" -int "$value" ;;
    float) xcrun simctl spawn "$device" defaults write "$BUNDLE_ID" "$key" -float "$value" ;;
    array)
      IFS=',' read -r -a values <<< "$value"
      xcrun simctl spawn "$device" defaults write "$BUNDLE_ID" "$key" -array "${values[@]}"
      ;;
    *) xcrun simctl spawn "$device" defaults write "$BUNDLE_ID" "$key" -string "$value" ;;
  esac
}

reset_synthetic_state() {
  local device="$1"
  xcrun simctl terminate "$device" "$BUNDLE_ID" 2>/dev/null || true
  for key in "${SCREENSHOT_KEYS[@]}"; do
    xcrun simctl spawn "$device" defaults delete "$BUNDLE_ID" "$key" 2>/dev/null || true
  done

  xcrun simctl spawn "$device" defaults write "$BUNDLE_ID" hasSeenParentOnboarding -bool true
  xcrun simctl spawn "$device" defaults write "$BUNDLE_ID" hubMode -string race
  xcrun simctl spawn "$device" defaults write "$BUNDLE_ID" raceDuration -float 60
  xcrun simctl spawn "$device" defaults write "$BUNDLE_ID" raceBest_60 -int 21
  xcrun simctl spawn "$device" defaults write "$BUNDLE_ID" raceLast_60 -int 18
  xcrun simctl spawn "$device" defaults write "$BUNDLE_ID" onlyWordsWithImages -bool true
  xcrun simctl spawn "$device" defaults write "$BUNDLE_ID" isUppercase -bool true
  xcrun simctl spawn "$device" defaults write "$BUNDLE_ID" letterVoice -string sounds
  xcrun simctl spawn "$device" defaults write "$BUNDLE_ID" mathAllowAdd -bool true
  xcrun simctl spawn "$device" defaults write "$BUNDLE_ID" mathAllowSub -bool false
  xcrun simctl spawn "$device" defaults write "$BUNDLE_ID" wordBoxes \
    -dict cat 3 cow 3 dog 3 fox 3 pig 3 sun 3
  xcrun simctl spawn "$device" defaults write "$BUNDLE_ID" wordSeenCounts \
    -dict cat 9 cow 8 dog 10 fox 7 pig 8 sun 9
}

capture() {
  local device="$1" output="$2"
  shift 2
  reset_synthetic_state "$device"

  local pair key value type
  for pair in "$@"; do
    key="${pair%%=*}"
    value="${pair#*=}"
    type="${value##*:}"
    value="${value%:*}"
    write_default "$device" "$key" "$value" "$type"
  done

  xcrun simctl launch "$device" "$BUNDLE_ID" \
    -AppleLanguages '(en)' -AppleLocale en_US >/dev/null
  sleep 5
  xcrun simctl io "$device" screenshot "$output" >/dev/null
  echo "captured $output"
}

capture_set() {
  local device="$1" output_dir="$2"
  mkdir -p "$output_dir"

  capture "$device" "$output_dir/01-home.png"
  capture "$device" "$output_dir/02-read.png" \
    screenshotLaunchGame=read:string screenshotWord=fox:string
  capture "$device" "$output_dir/03-phonics-settings.png" \
    screenshotLaunchGame=read:string screenshotWord=cat:string \
    screenshotShowSettings=true:bool
  capture "$device" "$output_dir/04-my-words.png" \
    screenshotShowStickers=true:bool
  capture "$device" "$output_dir/05-listen-and-pick.png" \
    screenshotLaunchGame=quiz:string screenshotColorIndex=5:int \
    screenshotGameWords=cat,dog,fox,pig:array screenshotQuizAnswer=fox:string
  capture "$device" "$output_dir/06-spell-it.png" \
    screenshotLaunchGame=spell:string screenshotColorIndex=3:int \
    screenshotGameWord=cat:string screenshotSpellTypedCount=1:int
  capture "$device" "$output_dir/07-race-results.png" \
    screenshotStartRace=true:bool screenshotRaceTab=quiz:string \
    screenshotRaceScore=24:int screenshotRaceRemaining=0:float \
    screenshotRaceFinished=true:bool screenshotColorIndex=4:int \
    screenshotGameWords=cat,dog,fox,pig:array screenshotQuizAnswer=fox:string
}

echo "Generating the Xcode project and building 1.12 (60) Release..."
xcodegen generate
xcodebuild -quiet -project 123words.xcodeproj -scheme Words123 \
  -configuration Release -sdk iphonesimulator \
  -destination "platform=iOS Simulator,id=$IPHONE_ID" \
  -derivedDataPath "$DERIVED_DATA" CODE_SIGNING_ALLOWED=NO build

for device in "$IPHONE_ID" "$IPAD_ID"; do
  xcrun simctl boot "$device" 2>/dev/null || true
  open -gj -a Simulator --args -CurrentDeviceUDID "$device" 2>/dev/null || true
  xcrun simctl bootstatus "$device" -b
  xcrun simctl uninstall "$device" "$BUNDLE_ID" 2>/dev/null || true
  xcrun simctl install "$device" "$APP_PATH"
  xcrun simctl status_bar "$device" override \
    --time '9:41' --batteryState charged --batteryLevel 100 \
    --wifiBars 3 --cellularBars 4 2>/dev/null || true
done

echo "Capturing iPhone 17 Pro Max portrait..."
capture_set "$IPHONE_ID" "$OUTPUT_ROOT/iPhone-6.9"

echo "Capturing iPad Pro 13-inch portrait..."
capture_set "$IPAD_ID" "$OUTPUT_ROOT/iPad-13"

echo "Capture complete: $OUTPUT_ROOT"
