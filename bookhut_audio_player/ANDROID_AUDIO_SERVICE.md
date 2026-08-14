# BookHut audio-service Android notes

For the current `audio_service` setup, keep these permissions in `android/app/src/main/AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.WAKE_LOCK" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK" />
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
```

Inside `<application>`:

```xml
<service
    android:name="com.ryanheise.audioservice.AudioService"
    android:foregroundServiceType="mediaPlayback"
    android:exported="true">
    <intent-filter>
        <action android:name="android.media.browse.MediaBrowserService" />
    </intent-filter>
</service>

<receiver
    android:name="com.ryanheise.audioservice.MediaButtonReceiver"
    android:exported="true">
    <intent-filter>
        <action android:name="android.intent.action.MEDIA_BUTTON" />
    </intent-filter>
</receiver>
```

If the project is using modern Flutter/Android Gradle tooling, compile Java/Kotlin against Java 17 rather than Java 8 to remove the obsolete source/target warning:

```gradle
android {
    compileOptions {
        sourceCompatibility JavaVersion.VERSION_17
        targetCompatibility JavaVersion.VERSION_17
    }
}
```

If Kotlin compiler options are configured explicitly, use JVM target 17 as well.

## Fixed issues in this version

- Bookmark data is persisted as JSON instead of `List.toString()`.
- Bookmark loading safely decodes JSON and handles malformed data.
- Resume position no longer depends on the incorrect `_isFirstLoad` condition.
- Stream subscriptions are cancelled when the screen is disposed/reinitialized.
- Single-file local playback uses `AudioSource.file` when a `file://` URI is supplied.
- Chapters use `MediaItem` metadata, so notification/lock-screen metadata can follow the current chapter.
- Previous/next actions are implemented in the central `AudioPlayerHandler`.
- `currentIndexStream` updates the active `MediaItem` when the chapter changes.
- Audio service initialization errors are no longer silently swallowed.
