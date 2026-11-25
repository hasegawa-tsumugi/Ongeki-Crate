plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "dev.tsumugi.songquery"
    compileSdk = flutter.compileSdkVersion
    // 各插件（jni / shared_preferences_android / sqflite_android /
    // url_launcher_android）都要求 28.2.13676358；高版本向后兼容，
    // 停在 27.1 每次构建都会刷一屏 NDK 版本告警。
    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "dev.tsumugi.songquery"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // **versionCode 固定，不随版本走**（2026-11-24 用户要求「build 号不要了」）。
        // 它是 Android 判定新旧的整数，不是给人看的版本 —— 本项目只在自用机侧载，
        // 同 code 同签名可以覆盖安装，不需要递增。以前靠 pubspec 的 `+N` 驱动，
        // 现在 pubspec 只放 versionName（如 0.1.2-beta1），这里写死一个常量。
        // 真要发上架版本时，再把它改成递增（商店才会校验）。
        versionCode = 12
        versionName = flutter.versionName
    }

    // Flutter 的 --target-platform 只过滤引擎产物，插件自带的预编译 .so
    // （dartjni / datastore 之类）仍会按全 ABI 打进包。defaultConfig 里的
    // ndk.abiFilters 在 AGP 9 上不生效（打出来还是三套），所以这里直接按
    // 包内路径排除。
    packaging {
        jniLibs {
            excludes += setOf("lib/armeabi-v7a/**", "lib/x86_64/**")
        }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
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
