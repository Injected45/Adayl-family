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
        // ⚠ REQUIRED BY flutter_local_notifications, and the build fails at
        //   checkReleaseAarMetadata without it — not at compile, so the error
        //   names an AAR rather than the package that needs it. Desugaring is
        //   what lets a library use java.time on Android versions that predate
        //   it, which is exactly what scheduling a notification needs.
        isCoreLibraryDesugaringEnabled = true
    }

    // The runtime half of the line above.
    dependencies {
        coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
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
        // ONE debug key for the whole team, committed on purpose.
        //
        // Google mints an ID token only for a registered package-name + SHA-1
        // pair. Android's default debug keystore is generated per MACHINE, so
        // every developer's `flutter run` produced a different signature and
        // Google refused all but the one machine whose fingerprint happened to
        // be registered — reported as "تم إلغاء تسجيل الدخول", which reads like
        // the user cancelled and is why this cost two rounds to find.
        //
        // Registering each developer's fingerprint does not scale. Sharing one
        // does: dev-debug.keystore is in the repository, so every clone signs
        // debug builds identically and the single Android OAuth client for
        // 17:65:5F:BF:C7:8A:62:25:43:EA:4E:28:71:D5:83:6A:38:A5:FE:E0 covers
        // everyone.
        //
        // Committing it is safe and deliberate: a debug keystore signs nothing
        // that can be published — Play refuses it — and its password is the
        // documented constant `android`. It is NOT the release key. That one is
        // app/android/key.properties + a keystore outside the repository, both
        // gitignored, and neither is needed to run the app.
        getByName("debug") {
            storeFile = rootProject.file("dev-debug.keystore")
            storePassword = "android"
            keyAlias = "androiddebugkey"
            keyPassword = "android"
        }

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
