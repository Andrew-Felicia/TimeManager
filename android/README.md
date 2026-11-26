# Flowtime for Android

This folder contains the native Android version of Flowtime. It is built with Kotlin and Jetpack Compose and can coexist with the iPhone app in `../ios`.

## Versioning

Flowtime uses semantic three-part versions. Small fixes increment the patch number (`1.0.0` → `1.0.1`), compatible feature updates increment the minor number, and only major redesigns or breaking changes increment the first number (`1.x.x` → `2.0.0`). Android's internal `versionCode` increases with every distributed APK so each build can update the previous one without removing user data.

## Open in Android Studio

1. Install the latest Android Studio.
2. Choose **Open** and select this `android` folder (not the repository root).
3. Let Gradle sync and install any requested Android SDK components.
4. Connect an Android phone with USB debugging enabled, select it in the device menu, and press **Run**.

## Command-line build

```sh
cd android
./gradlew assembleDebug
```

The debug APK is produced at `app/build/outputs/apk/debug/app-debug.apk`.

## Installing an update without losing data

1. In the existing app, use **Insights → Settings → Export Data** as a safety backup.
2. Open the new APK and install it directly over the existing Flowtime app.
3. Do not uninstall the old version and do not clear its storage first.

Android preserves Flowtime's local tasks, events, categories, timer progress, insights, and settings when the package name and signing certificate match and the version code increases. This project uses a locally preserved update key from `signing.properties`; both it and the key file are intentionally ignored by Git.

## Moving data between iPhone and Android

In Flowtime, open **Insights → Settings → Export Data** on the old device. Copy the JSON file to the other device, then choose **Import Data**. Import replaces the current Flowtime data after confirmation.
