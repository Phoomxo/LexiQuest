import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

val releaseSigningReady = keystoreProperties["storeFile"] != null &&
    keystoreProperties["storePassword"] != null &&
    keystoreProperties["keyAlias"] != null &&
    keystoreProperties["keyPassword"] != null

android {
    namespace = "com.lexiquest.app"
    compileSdk = flutter.compileSdkVersion
    // Pinned because the APK integrity gate verifies locally compiled LiteRT
    // custom-op binaries byte-for-byte.
    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.lexiquest.app"
        // Android 8.0 (API 26): Android 7 (API 24/25) reached security-patch
        // EOL in 2019. Raising the floor to 26 drops legacy crypto surface and
        // matches every plugin floor (highest is flutter_tts at 24) and every
        // procured trial device (vivo V2041 = API 33, HONOR DNP-NX9 = API 36).
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (releaseSigningReady) {
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

gradle.taskGraph.whenReady {
    val isReleaseArtifact = allTasks.any { task ->
        task.name.startsWith("packageRelease") ||
            task.name.startsWith("bundleRelease")
    }
    if (isReleaseArtifact && !releaseSigningReady) {
        throw GradleException(
            "Release signing is not configured. Create android/key.properties " +
                "(see android/key.properties.example) with storeFile, " +
                "storePassword, keyAlias and keyPassword before building a " +
                "release artifact. Debug builds are unaffected.",
        )
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation(platform("com.google.firebase:firebase-bom:34.16.0"))
}
