plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.anxiety_mobile_app"
    
    // Use a stable, widely-installed SDK to ensure attribute availability
                compileSdk = 36

    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_1_8
        targetCompatibility = JavaVersion.VERSION_1_8
        
        // FIX 2: Enabled Core Library Desugaring (Required by Local Notifications)
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = "1.8"
    }

    sourceSets {
        getByName("main").java.srcDirs("src/main/kotlin")
    }

    defaultConfig {
        applicationId = "com.example.anxiety_mobile_app"
        minSdk = flutter.minSdkVersion
                    // Match Compile SDK
                    targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        setProperty("archivesBaseName", "Anxiety_Research_App")
    }

    buildTypes {
        release {
            // Using debug keys for simplicity so you can install it immediately
            signingConfig = signingConfigs.getByName("debug")
            isMinifyEnabled = false 
            isShrinkResources = false
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // FIX 4: Added the required library for Desugaring
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
}
