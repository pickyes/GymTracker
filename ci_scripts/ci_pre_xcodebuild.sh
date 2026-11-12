#!/bin/sh
# Xcode Cloud: give every cloud build a unique, increasing build number so
# TestFlight accepts each upload. Uses the same timestamp scheme
# (YYYYMMDDHHMM) as scripts/upload-testflight.sh, so local and cloud
# uploads never collide or go backwards. Rewrites CURRENT_PROJECT_VERSION
# in the cloud checkout only — nothing is committed back.
set -e
if [ -n "$CI_XCODE_CLOUD" ] || [ -n "$CI_BUILD_NUMBER" ]; then
  BUILD_NUMBER=$(TZ=America/New_York date +%Y%m%d%H%M)
  sed -i '' -E "s/CURRENT_PROJECT_VERSION = [0-9]+;/CURRENT_PROJECT_VERSION = $BUILD_NUMBER;/" \
    "$CI_PRIMARY_REPOSITORY_PATH/GymTracker.xcodeproj/project.pbxproj"
  echo "Build number set to $BUILD_NUMBER"
fi
