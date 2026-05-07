import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

android {
    namespace = "no.skybyn.app"
    // Use compileSdk 36 (Android 16 / BAKLAVA) - required for sqflite_android 2.4.2+
    compileSdk = 36
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_21
        targetCompatibility = JavaVersion.VERSION_21
        // Desugaring needed for some plugins even with minSdk 26+
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_21.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "no.skybyn.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // minSdk 26 = Android 8.0 (Oreo) - reduces APK size by removing desugaring and compatibility libraries
        // Still covers ~95%+ of active Android devices
        minSdk = 26
        // targetSdk 35 remains for broad compatibility, while compileSdk is 36
        targetSdk = 35
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // Support only modern 64-bit ARM architecture (covers 99% of modern devices)
        // This significantly reduces APK size compared to universal builds
        ndk {
            abiFilters.clear()
            abiFilters.add("arm64-v8a")
        }
    }

    // Load keystore properties from key.properties file
    // key.properties is located at the project root (Skybyn_APP/key.properties)
    val keystorePropertiesFile = rootProject.file("../key.properties")
    val keystoreProperties = Properties()
    if (keystorePropertiesFile.exists()) {
        keystoreProperties.load(FileInputStream(keystorePropertiesFile))
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
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
            // Ensure APK is properly aligned and optimized
            isDebuggable = false
        }
        debug {
            // Explicitly set debug signing
            signingConfig = signingConfigs.getByName("debug")
        }
    }
    
    // Disable APK splits to ensure a clean build with focused architectures
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

    // Don't compress font files so Typeface.createFromAsset() can open them
    androidResources {
        noCompress += listOf(".otf", ".ttf")
    }

    // Forcefully exclude unused native architectures from the final binary
    // This is required when plugins (like WebRTC) include multiple ABIs that ignore abiFilters
    packaging {
        jniLibs {
            excludes.add("lib/armeabi-v7a/**")
            excludes.add("lib/x86/**")
            excludes.add("lib/x86_64/**")
        }
    }

    // Suppress deprecation warnings from third-party dependencies (flutter_webrtc uses deprecated APIs)
    tasks.withType<JavaCompile>().configureEach {
        options.compilerArgs.add("-Xlint:-deprecation")
        options.compilerArgs.add("-Xlint:-unchecked")
    }
}

// Global configuration to exclude conflicting Play Core dependencies
configurations.all {
    exclude(group = "com.google.android.play", module = "core-common")
}

dependencies {
    // Firebase BOM for version management
    implementation(platform("com.google.firebase:firebase-bom:33.7.0"))
    // Play Core library for Flutter deferred components (referenced by Flutter engine)
    // This is required to prevent R8 errors when minifyEnabled is true
    implementation("com.google.android.play:core:1.10.3")
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}
