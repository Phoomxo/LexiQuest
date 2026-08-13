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

val storeFileValue =
    keystoreProperties.getProperty("storeFile")?.trim().orEmpty()
val releaseStoreFile = storeFileValue
    .takeIf { it.isNotEmpty() }
    ?.let { rootProject.file(it).canonicalFile }
val releaseSigningReady = releaseStoreFile?.isFile == true &&
    listOf("storePassword", "keyAlias", "keyPassword").all { key ->
        !keystoreProperties.getProperty(key).isNullOrBlank()
    }

val releaseSourceCommit = providers
    .gradleProperty("lexiquestSourceCommit")
    .orNull?.trim()?.lowercase().orEmpty()
val releaseBuildId = providers
    .gradleProperty("lexiquestBuildId")
    .orNull?.trim()?.lowercase().orEmpty()
val releaseModelSha256 = providers
    .gradleProperty("lexiquestModelSha256")
    .orNull?.trim()?.uppercase().orEmpty()
val releaseProvenanceReady =
    Regex("^[0-9a-f]{40}$").matches(releaseSourceCommit) &&
        Regex("^[0-9a-f]{12}$").matches(releaseBuildId) &&
        releaseBuildId == releaseSourceCommit.take(12) &&
        Regex("^[0-9A-F]{64}$").matches(releaseModelSha256)

android {
    namespace = "com.lexiquest.app"
    compileSdk = flutter.compileSdkVersion
    // Pinned because the APK integrity gate verifies locally compiled LiteRT
    // custom ops with build-id-descriptor-insensitive canonical hashing while
    // retaining exact source, ABI, mode, and all other byte integrity.
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
                storeFile = releaseStoreFile
                storePassword = keystoreProperties["storePassword"] as String
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            manifestPlaceholders.putAll(
                mapOf(
                    "lexiquestSourceCommit" to
                        releaseSourceCommit.ifEmpty { "missing" },
                    "lexiquestBuildId" to
                        releaseBuildId.ifEmpty { "missing" },
                    "lexiquestModelSha256" to
                        releaseModelSha256.ifEmpty { "missing" },
                ),
            )
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
    if (isReleaseArtifact && !releaseProvenanceReady) {
        throw GradleException(
            "Release provenance is missing or invalid. Use " +
                "tool/cli/package-field-release.ps1.",
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
