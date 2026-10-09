import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// The release signing key lives outside the repository: in android/key.properties (git-ignored) or
// in these environment variables (the release workflow sets them from GitHub secrets). See
// docs/ANDROID_RELEASE.md. Without a key a release build is signed with the debug key and must
// never be handed to anyone.
val keyProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) FileInputStream(file).use { load(it) }
}

fun signingValue(env: String, property: String): String? =
    System.getenv(env)?.takeIf { it.isNotBlank() } ?: keyProperties.getProperty(property)

android {
    namespace = "com.example.erp_system"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // The identity of the app on a device and, later, in Google Play. It cannot change once
        // people have installed the app (a different id is a different app): choose the final one
        // before the first real client gets the APK. The code package (namespace) stays as it is.
        applicationId = "app.erpsystem.mobile"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            val path = signingValue("ANDROID_KEYSTORE_PATH", "storeFile")
            if (path != null) {
                storeFile = file(path)
                storePassword = signingValue("ANDROID_KEYSTORE_PASSWORD", "storePassword")
                keyAlias = signingValue("ANDROID_KEY_ALIAS", "keyAlias")
                keyPassword = signingValue("ANDROID_KEY_PASSWORD", "keyPassword")
            }
        }
    }

    buildTypes {
        release {
            val releaseKey = signingConfigs.getByName("release")
            if (System.getenv("ANDROID_REQUIRE_RELEASE_SIGNING") == "true" && releaseKey.storeFile == null) {
                throw GradleException("No release signing key: set ANDROID_KEYSTORE_PATH and the other signing variables.")
            }
            signingConfig = if (releaseKey.storeFile != null) releaseKey else signingConfigs.getByName("debug")
            // Code shrinking is off until the camera scanner, printing and file flows have been
            // tried on a device with a release build; switch it on afterwards to make the app smaller.
            isMinifyEnabled = false
            isShrinkResources = false
        }
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
