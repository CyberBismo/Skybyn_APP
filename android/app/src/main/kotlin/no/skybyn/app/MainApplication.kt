package no.skybyn.app

import android.app.Application
import android.util.Log

class MainApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        
        // Note: Native Android system logs (ViewRootImpl, InputMethodManager, Firebase, etc.)
        // cannot be suppressed from app code as they come from the Android system itself.
        // 
        // To filter logs in your IDE/console:
        // 1. Android Studio: Use Logcat filter: `package:mine level:error,assert` or `tag:SKYBYN`
        // 2. VS Code: Configure logcat filter in settings
        // 3. Command line: `adb logcat *:E *:W flutter:V *:S` (only errors, warnings, and Flutter verbose)
        // 4. Or use: `adb logcat | grep -E "SKYBYN|flutter"` (only SKYBYN and Flutter logs)
        //
        // Flutter/Dart logs are already filtered by the zone in main.dart (only [SKYBYN] prefix shows)
    }
}
