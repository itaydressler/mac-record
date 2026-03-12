#!/bin/bash
set -e

APP=$(find ~/Library/Developer/Xcode/DerivedData/MacRecord-*/Build/Products/Debug/MacRecord.app -maxdepth 0 2>/dev/null | head -1)

if [ -z "$APP" ]; then
  echo "App not built yet. Run: xcodebuild -scheme MacRecord -configuration Debug build"
  exit 1
fi

pkill -x MacRecord 2>/dev/null || true
sleep 0.5
open "$APP"
echo "Launched $APP"
