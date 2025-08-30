# Firebase App Distribution Auto-Update Setup

This guide explains how to set up Firebase App Distribution for automatic app updates on Android.

## What's Been Implemented

✅ **Auto-update service** - Checks for updates automatically  
✅ **Update dialog** - Shows update information to users  
✅ **Progress tracking** - Shows download and installation progress  
✅ **Menu integration** - "Check for Updates" option in user menu  
✅ **Error handling** - Graceful fallback when service unavailable  
✅ **Permission checking** - Verifies install permissions before updates  

## Setup Steps

### 1. Firebase Console Setup

1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Select your project (or create one)
3. Go to **App Distribution** in the left sidebar
4. Click **Get started**

### 2. Add Testers

1. In App Distribution, go to **Testers & groups**
2. Click **Add testers**
3. Add email addresses of testers
4. Create tester groups if needed

### 3. Upload Your App

1. Build your APK: `flutter build apk --release`
2. In App Distribution, click **New release**
3. Upload your APK file
4. Add release notes
5. Select testers/groups
6. Click **Distribute**

### 4. Configure Your App

The app is already configured to:
- Check for updates automatically on startup
- Show update dialogs when updates are available
- Handle download and installation progress
- Provide manual update check option

## How It Works

### Permission Handling
- **Before checking for updates**, the app verifies installation permissions
- **User-friendly permission dialog** explains why the permission is needed
- **Automatic system permission request** for "Install from unknown sources"
- **Graceful fallback** if permissions are not granted
- **Clear user education** about security implications

### Automatic Updates
- App checks for updates 5 seconds after startup
- Only works on Android devices
- Requires user permission for "Install from unknown sources"

### Manual Updates
- Users can check for updates via menu: **Menu → Check for Updates**
- Shows current vs. latest version
- Displays release notes if available

### Update Process
1. **Permission Check** - App verifies installation permissions
2. **Permission Request** - Shows user-friendly dialog explaining why permission is needed
3. **System Permission** - Requests Android system permission for unknown sources
4. **Check** - App queries Firebase for available updates
5. **Download** - APK downloads in background with progress
6. **Install** - App prompts user to install update
7. **Restart** - App restarts with new version

## Permissions Required

The following permissions have been added to `AndroidManifest.xml`:
```xml
<uses-permission android:name="android.permission.REQUEST_INSTALL_PACKAGES" />
<uses-permission android:name="android.permission.INSTALL_PACKAGES" />
```

## Testing

1. **Build test APK**: `flutter build apk --debug`
2. **Upload to Firebase**: Use App Distribution console
3. **Test on device**: Install APK and check for updates
4. **Verify flow**: Update dialog should appear

## Troubleshooting

### Common Issues

**"Firebase App Distribution not available"**
- Check if Firebase project is properly configured
- Verify App Distribution is enabled
- Check internet connection

**"No updates available"**
- Verify APK is uploaded to Firebase
- Check if tester email matches device
- Ensure release is distributed to correct group

**Update fails to install**
- Check if "Install from unknown sources" is enabled
- Verify APK signature matches
- Check device storage space

### Debug Logs

The service provides detailed logging:
- `✅ [AutoUpdate]` - Success messages
- `⚠️ [AutoUpdate]` - Warning messages  
- `❌ [AutoUpdate]` - Error messages
- `🔄 [AutoUpdate]` - Progress messages

## Security Notes

- Updates are signed with your app's signing key
- Only distributed to authorized testers
- Requires user consent for installation
- No automatic installation without user approval

## Next Steps

1. **Set up Firebase project** with App Distribution
2. **Add testers** to your distribution group
3. **Upload first APK** to test the system
4. **Distribute to testers** and verify updates work
5. **Monitor usage** in Firebase console

## Support

For Firebase App Distribution issues:
- [Firebase Documentation](https://firebase.google.com/docs/app-distribution)
- [Flutter Plugin Documentation](https://pub.dev/packages/firebase_app_distribution)
- [Firebase Support](https://firebase.google.com/support)
