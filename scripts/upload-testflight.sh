#!/bin/sh
# Archive GymTracker and upload it to TestFlight (internal testing only).
# Run from Terminal (uses your Xcode account + signing).
# The build number is set automatically to a timestamp (YYYYMMDDHHMM), so
# every upload is newer than the last — no manual bump needed.
# Uses its own DerivedData (build/DerivedData) so it never collides with
# a build Xcode is running at the same time.
set -e
cd "$(dirname "$0")/.."
BUILD_NUMBER=$(date +%Y%m%d%H%M)
echo "Building GymTracker build $BUILD_NUMBER"
rm -rf build/GymTracker.xcarchive
xcodebuild archive \
  -project GymTracker.xcodeproj -scheme GymTracker -configuration Release \
  -destination "generic/platform=iOS" \
  -archivePath build/GymTracker.xcarchive -allowProvisioningUpdates \
  -derivedDataPath build/DerivedData \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER"
xcodebuild -exportArchive \
  -archivePath build/GymTracker.xcarchive \
  -exportOptionsPlist scripts/ExportOptions.plist \
  -exportPath build/export -allowProvisioningUpdates
echo "Uploaded build $BUILD_NUMBER. Watch App Store Connect → TestFlight for processing."
