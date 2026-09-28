allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    if (providers.gradleProperty("nativeStaleCfTest").orNull == "true") {
        rootProject.layout.projectDirectory.dir("../build/native-stale/S01-CF/gradle")
    } else if (providers.gradleProperty("nativeDraftCeTest").orNull == "true") {
        rootProject.layout.projectDirectory.dir("../build/native-draft/S01-CE/gradle")
    } else if (providers.gradleProperty("nativeDraftCdTest").orNull == "true") {
        rootProject.layout.projectDirectory.dir("../build/native-draft/S01-CD/gradle")
    } else if (providers.gradleProperty("nativeDraftTest").orNull == "true") {
        rootProject.layout.projectDirectory.dir("../build/native-draft/S01-CB/gradle")
    } else if (providers.gradleProperty("nativeTerminalTest").orNull == "true") {
        rootProject.layout.projectDirectory.dir("../build/native-terminal/S01-CA/gradle")
    } else if (providers.gradleProperty("nativeRecoveryTest").orNull == "true") {
        rootProject.layout.projectDirectory.dir("../build/native-recovery/S01-BZ/gradle")
    } else if (providers.gradleProperty("nativeTodayTest").orNull == "true") {
        // BY must retain every previous APK at its original path.
        rootProject.layout.projectDirectory.dir("../build/native-today/S01-BY/gradle")
    } else rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
