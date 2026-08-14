# Flutter's own engine classes are referenced reflectively from native code.
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Google Sign-In and the Play services auth flow.
-keep class com.google.android.gms.auth.** { *; }
-keep class com.google.android.gms.common.** { *; }

# flutter_secure_storage relies on the Android Keystore via reflection.
-keep class androidx.security.crypto.** { *; }

# Keep annotations that R8 would otherwise strip, which breaks plugin lookup.
-keepattributes *Annotation*, Signature, InnerClasses, EnclosingMethod

# Silence warnings for classes that are only present on other platforms.
-dontwarn javax.annotation.**

# Flutter's engine references the Play Store deferred-components API
# unconditionally, but the dependency ships only with `com.google.android.play:core`.
# This app has no deferred components, so the references are genuinely dead and
# R8 only needs telling not to fail on them. Without this, enabling minification
# breaks the release build with a wall of "Missing class" errors.
-dontwarn com.google.android.play.core.**
-dontwarn io.flutter.embedding.android.FlutterPlayStoreSplitApplication
-dontwarn io.flutter.embedding.engine.deferredcomponents.**
