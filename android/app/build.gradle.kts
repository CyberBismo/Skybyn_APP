plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "no.skybyn.app"
    // Use compileSdk 36 (Android 16) - required for sqflite_android 2.4.2+ which hardcodes compileSdk 36
    // Note: targetSdk remains at 34 for compatibility
    compileSdk = 36
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "no.skybyn.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // minSdk 21 = Android 5.0 (Lollipop) - supports ~99% of active Android devices
        minSdk = 21
        // targetSdk 36 = Android 16 - updated to match compileSdk for latest compatibility
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        
        // Support only ARM architectures (covers 99%+ of devices)
        // x86/x86_64 are mainly for emulators and very old devices
        // Removing them reduces APK size by ~50%
        ndk {
            abiFilters += listOf("armeabi-v7a", "arm64-v8a")
        }
    }

    // Load keystore properties from key.properties file
    // key.properties is located at the project root (Skybyn_APP/key.properties)
    val keystorePropertiesFile = rootProject.file("../key.properties")
    val keystoreProperties = java.util.Properties()
    if (keystorePropertiesFile.exists()) {
        keystoreProperties.load(java.io.FileInputStream(keystorePropertiesFile))
    }

    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                // storeFile path is relative to android/app/ directory: "../upload-keystore.jks" (in android/ folder)
                val keystorePath = keystoreProperties["storeFile"] as String?
                storeFile = keystorePath?.let { file(it) }
                storePassword = keystoreProperties["storePassword"] as String
                // Enable both v1 and v2 signing for maximum compatibility
                enableV1Signing = true
                enableV2Signing = true
            }
        }
        // Ensure debug signing is always available
        getByName("debug") {
            // Debug signing is automatically configured by Android
        }
    }

    buildTypes {
        release {
            // Always use a signing config - prefer release, fallback to debug
            signingConfig = if (keystorePropertiesFile.exists() && 
                keystoreProperties.containsKey("keyAlias") &&
                keystoreProperties.containsKey("storeFile")) {
                signingConfigs.getByName("release")
            } else {
                // Use debug signing if release keystore not configured
                // This ensures APK is always signed (even if with debug key)
                signingConfigs.getByName("debug")
            }
            isMinifyEnabled = false
            isShrinkResources = false
            // Ensure APK is properly aligned and optimized
            isDebuggable = false
        }
        debug {
            // Explicitly set debug signing
            signingConfig = signingConfigs.getByName("debug")
        }
    }
    
    // Disable APK splits to ensure a single universal APK installable on all devices
    splits {
        abi {
            isEnable = false
        }
        density {
            isEnable = false
        }
    }
    
    // Lint options to prevent build failures
    lint {
        checkReleaseBuilds = false
        abortOnError = false
    }

    // Suppress deprecation warnings from third-party dependencies (flutter_webrtc uses deprecated APIs)
    tasks.withType<JavaCompile>().configureEach {
        options.compilerArgs.add("-Xlint:-deprecation")
        options.compilerArgs.add("-Xlint:-unchecked")
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
}

flutter {
    source = "../.."
}
