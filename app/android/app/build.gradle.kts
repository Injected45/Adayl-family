import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing is read from android/key.properties, which is gitignored
// along with the keystore itself. Nothing secret belongs in this file — it is
// committed, and a password here would be a password published.
//
// To create the keystore and this file, see app/README.md.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
val hasSigningConfig = keystorePropertiesFile.exists()
if (hasSigningConfig) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "ly.adayl.family_app"
    // Pinned rather than flutter.compileSdkVersion, which is 36 in Flutter 3.41.
    // flutter_secure_storage compiles against 37 and the build FAILS outright,
    // not with a warning — and it is not an optional dependency here: it is where
    // the Supabase refresh token is kept, off the filesystem and in the Android
    // keystore.
    //
    // Raising compileSdk only changes which SDK the code is COMPILED against;
    // Android SDKs are backward compatible, and targetSdk/minSdk are untouched,
    // so nothing about runtime behaviour or device support moves.
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "ly.adayl.family_app"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // The association is Libyan; Arabic is the only locale the app ships.
        resourceConfigurations += listOf("ar", "en")
    }

    signingConfigs {
        if (hasSigningConfig) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = keystoreProperties["storeFile"]?.let { file(it) }
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // Falls back to debug keys when key.properties is absent, so
            // `flutter run --release` still works for a developer. A store
            // upload requires the real keystore — and Google Sign-In will fail
            // on a debug-signed release unless that certificate's SHA-1 is
            // registered too.
            signingConfig = if (hasSigningConfig) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

flutter {
    source = "../.."
}
