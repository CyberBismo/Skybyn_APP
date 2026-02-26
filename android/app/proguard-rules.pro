# Flutter wrapper
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }

# Fix for androidx.window Missing Classes
# These are optional dependencies for older Android versions or OEM sidecar APIs.
# R8 warns about them missing, but they are safe to ignore unless we're exactly
# using the folding feature on those specific devices directly.
-dontwarn androidx.window.**
-keep class androidx.window.** { *; }
