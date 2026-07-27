# 123 Words — iOS Reading App for Kids

A joyful reading app for grandkids. Swipe a word, hear it spoken, watch each letter light up as it spells.

## Stack
- SwiftUI, iOS 17+, ObservableObject
- AVSpeechSynthesizer for TTS
- XcodeGen (`project.yml` is source of truth)
- Bundle ID: `com.123words.app`, Version 1.0 (Build 28)

## Common Commands
- `xcodegen generate` — regenerate Xcode project after editing project.yml
- `xcodebuild -scheme Words123 -destination 'id=<SIM_UUID>' build` — build for simulator
- Archive + upload: see below

## TestFlight Upload
```bash
xcodebuild -scheme Words123 -destination 'generic/platform=iOS' \
  -archivePath build/Words123.xcarchive archive

xcodebuild -exportArchive \
  -archivePath build/Words123.xcarchive \
  -exportOptionsPlist /tmp/ExportOptions123.plist \
  -exportPath build/export \
  -allowProvisioningUpdates \
  -authenticationKeyPath ~/.private_keys/AuthKey_MN6H2P6385.p8 \
  -authenticationKeyID MN6H2P6385 \
  -authenticationKeyIssuerID 69a6de6f-2572-47e3-e053-5b8c7c11a4d1

xcrun altool --upload-app -f build/export/123words.ipa -t ios \
  --apiKey MN6H2P6385 \
  --apiIssuer 69a6de6f-2572-47e3-e053-5b8c7c11a4d1
```

ExportOptions123.plist lives at /tmp/ExportOptions123.plist — recreate if needed:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>app-store-connect</string>
  <key>teamID</key><string>NEAY582ME4</string>
  <key>signingStyle</key><string>automatic</string>
  <key>destination</key><string>export</string>
</dict></plist>
```

## Version Management
- Bump `CURRENT_PROJECT_VERSION` in `project.yml` before every TestFlight build
- Run `xcodegen generate` after bumping

## Website
GitHub Pages: https://billdonner.github.io/123words/
- `docs/index.html` — kid-friendly landing page
- `docs/privacy.html` — privacy policy
- `docs/support.html` — support page

## App Store Copy
See `AppStore/metadata.md` for name, subtitle, description, keywords.
Screenshots in `AppStore/Screenshots/`.
