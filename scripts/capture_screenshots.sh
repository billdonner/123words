#!/usr/bin/env bash
# Deterministic App Store capture set for the 1.12 UI refresh.
#
# Writes only to marketing/screenshots/2026-08-15-16/raw. It never changes
# the published AppStore/Screenshots baseline or anything in App Store Connect.
set -euo pipefail

BUNDLE_ID="com.123words.app"
IPHONE_ID="${IPHONE_ID:-F7030DEA-CC5E-4F5F-8A53-65774CDDC775}"
IPAD_ID="${IPAD_ID:-09EAF64C-1949-42FD-95D7-32AAD32C2745}"
DERIVED_DATA="${CAPTURE_DERIVED_DATA:-/private/tmp/123words-screenshot-derived}"
OUTPUT_ROOT="${CAPTURE_OUTPUT_ROOT:-marketing/screenshots/2026-08-15-16/raw}"
APP_PATH="$DERIVED_DATA/Build/Products/Release-iphonesimulator/123words.app"

capture() {
  local device="$1" output="$2"
  shift 2
  xcrun simctl terminate "$device" "$BUNDLE_ID" 2>/dev/null || true

  # NSArgumentDomain values exist only for this launch, so no screenshot
  # hook or synthetic state can leak into the next scenario.
  local launch_args=(
    -AppleLanguages '(en)' -AppleLocale en_US
    -hasSeenParentOnboarding YES -hubMode race
    -raceDuration 60 -raceBest_60 21 -raceLast_60 18
    -onlyWordsWithImages YES -isUppercase YES -letterVoice sounds
    -mathAllowAdd YES -mathAllowSub NO -screenshotSyntheticMastery YES
  )

  local pair key value type
  for pair in "$@"; do
    key="${pair%%=*}"
    value="${pair#*=}"
    type="${value##*:}"
    value="${value%:*}"
    launch_args+=("-$key" "$value")
  done

  xcrun simctl launch "$device" "$BUNDLE_ID" "${launch_args[@]}" >/dev/null
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
