#!/bin/bash

# Navigate to the app directory
PROJECT_DIR="/Users/bismo/development/Skybyn_APP"
cd "$PROJECT_DIR" || exit

echo "Building Flutter APK for release..."
flutter build apk --release

if [ $? -eq 0 ]; then
    echo "Build successful! Copying APK to SMB share..."
    
    # Define destination path
    DEST_PATH="/Volumes/FD/htdocs/skybyn/app/android/skybyn.apk"
    
    # Check if the destination directory exists (suggesting the remote share is mounted)
    if [ -d "/Volumes/FD/htdocs/skybyn/app/android" ]; then
        cp build/app/outputs/flutter-apk/app-release.apk "$DEST_PATH"
        
        if [ $? -eq 0 ]; then
            echo "Successfully copied APK to $DEST_PATH"
        else
            echo "Error: Failed to copy APK to destination."
            exit 1
        fi
    else
        echo "Error: Destination directory /Volumes/FD/htdocs/skybyn/app/android does not exist."
        echo "Please ensure the SMB share (smb://web-server/FD/htdocs) is mounted locally at /Volumes/FD."
        exit 1
    fi
else
    echo "Error: Flutter build failed."
    exit 1
fi
