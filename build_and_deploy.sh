#!/bin/bash

PROJECT_DIR="E:/htdocs/skybyn/app/flutter_project/Skybyn_APP"
cd "$PROJECT_DIR" || exit

echo "Building Flutter APK for release..."
flutter build apk --release

if [ $? -eq 0 ]; then
    DEST="E:/htdocs/skybyn/app/android/skybyn.apk"
    cp build/app/outputs/flutter-apk/app-release.apk "$DEST"
    if [ $? -eq 0 ]; then
        echo "Successfully copied APK to $DEST"
    else
        echo "Error: Failed to copy APK."
        exit 1
    fi
else
    echo "Error: Flutter build failed."
    exit 1
fi
