#!/bin/bash

# Skybyn Release Build Script
# Usage: ./build_release.sh [version] [build_number]

# Set default values
VERSION=${1:-"1.0.0"}
BUILD_NUMBER=${2:-"1"}

echo "Building Skybyn Release..."
echo "Version: $VERSION"
echo "Build Number: $BUILD_NUMBER"

# Create output directory
mkdir -p build/releases

# Build Android APK
echo "Building Android APK..."
flutter build apk \
  --build-name=$VERSION \
  --build-number=$BUILD_NUMBER \
  --output-file=build/releases/Skybyn-v$VERSION.apk

# Build Android App Bundle
echo "Building Android App Bundle..."
flutter build appbundle \
  --build-name=$VERSION \
  --build-number=$BUILD_NUMBER \
  --output-file=build/releases/Skybyn-v$VERSION.aab

# Build iOS (if on macOS)
if [[ "$OSTYPE" == "darwin"* ]]; then
    echo "Building iOS..."
    flutter build ios \
      --build-name=$VERSION \
      --build-number=$BUILD_NUMBER
fi

echo "Build completed! Files are in build/releases/"
ls -la build/releases/
