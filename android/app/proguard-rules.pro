# Flutter wrapper
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }

# Keep Firebase classes
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
# Keep Firebase KTX classes (required by firebase_app_distribution)
# The Firebase KTX class is provided by firebase-common-ktx
-keep class com.google.firebase.ktx.** { *; }
-keep class com.google.firebase.ktx.Firebase { *; }
-keepclassmembers class com.google.firebase.ktx.Firebase {
    *;
}
# Keep app distribution classes
-keep class com.google.firebase.appdistribution.** { *; }
# Keep app distribution KTX extension methods
-keep class com.google.firebase.appdistribution.ktx.** { *; }
# If Firebase KTX class is missing, suppress the warning (it may be optional)
-dontwarn com.google.firebase.ktx.Firebase

# Keep Agora RTC classes
-keep class io.agora.** { *; }

# Keep WebRTC classes
-keep class org.webrtc.** { *; }

# Keep native methods
-keepclasseswithmembernames class * {
    native <methods>;
}

# Keep Parcelable implementations
-keep class * implements android.os.Parcelable {
    public static final android.os.Parcelable$Creator *;
}

# Keep Serializable classes
-keepclassmembers class * implements java.io.Serializable {
    static final long serialVersionUID;
    private static final java.io.ObjectStreamField[] serialPersistentFields;
    private void writeObject(java.io.ObjectOutputStream);
    private void readObject(java.io.ObjectInputStream);
    java.lang.Object writeReplace();
    java.lang.Object readResolve();
}

# Keep annotation default values
-keepattributes AnnotationDefault

# Keep line numbers for stack traces
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile

# Flutter deferred components (Play Store split install)
# Keep Play Core classes that Flutter references
-keep class com.google.android.play.core.splitcompat.** { *; }
-keep class com.google.android.play.core.splitinstall.** { *; }
-keep class com.google.android.play.core.tasks.** { *; }

# Keep Flutter deferred component manager classes
-keep class io.flutter.embedding.engine.deferredcomponents.** { *; }
-keep class io.flutter.embedding.android.FlutterPlayStoreSplitApplication { *; }

