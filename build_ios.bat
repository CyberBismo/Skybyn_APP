@echo off
echo ========================================
echo Building Skybyn iOS App...
echo ========================================

REM Change to the Flutter project directory
cd /d "E:\htdocs\skybyn\app\flutter_project\Skybyn_APP"
echo Current directory: %CD%

REM Clean previous builds
echo.
echo Cleaning previous builds...
flutter clean

REM Get dependencies
echo.
echo Getting dependencies...
flutter pub get

REM Build iOS app
echo.
echo Building iOS app...
flutter build ios --release --no-codesign

REM Create target directory if it doesn't exist
echo.
echo Creating target directory...
if not exist "E:\htdocs\skybyn\app\ios" (
    mkdir "E:\htdocs\skybyn\app\ios"
)

REM Copy iOS files to target location
echo.
echo Copying iOS files to target location...
if exist "build\ios\Release-iphoneos\Runner.app" (
    echo iOS app built successfully!
    echo.
    echo ========================================
    echo ✅ iOS build completed successfully!
    echo 📱 App location: build\ios\Release-iphoneos\Runner.app
    echo ========================================
    echo.
    echo Next steps:
    echo 1. Open Runner.xcworkspace in Xcode
    echo 2. Configure signing and provisioning
    echo 3. Archive and export as Ad Hoc distribution
    echo 4. Upload the .ipa file to E:\htdocs\skybyn\app\ios\
    echo 5. Update the manifest.plist with the correct URL
) else (
    echo.
    echo ❌ iOS app not found!
    echo Please check the build output above for errors.
)

echo.
pause
