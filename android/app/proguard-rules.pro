# Kopi Kompas — R8 keep rules.
#
# Minification deletes anything it cannot see being used. Flutter plugins are
# reached from native code and reflection, so R8 cannot see those paths and
# would strip them. The Flutter tool ships most of these, but the ones below
# are the plugins this app uses.

# flutter_local_notifications reaches its receivers by name from the manifest,
# and deserialises scheduled notifications with Gson.
-keep class com.dexterous.** { *; }
-keep class * extends android.app.Service
-keep class * extends android.content.BroadcastReceiver

# sqflite and shared_preferences are plain method channels, but their
# generated registrants are referenced reflectively.
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.plugin.** { *; }

# Gson, used by flutter_local_notifications, needs its type tokens intact.
-keepattributes Signature
-keepattributes *Annotation*
-dontwarn com.google.gson.**
