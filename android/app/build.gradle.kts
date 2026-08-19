import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// 正式签名配置(android/key.properties,已 gitignore)
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
// 侧载验证时通过 Gradle 属性启用,避免 release 包覆盖已安装的 debug 包。
val sideBySideRelease =
    providers.gradleProperty("sideBySideRelease").orNull == "true" ||
        System.getenv("LKAPP_SIDE_BY_SIDE_RELEASE") == "true"
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "moe.yutro.yomiru"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "moe.yutro.yomiru"
        minSdk = 24
        targetSdk = 35
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String?
            keyPassword = keystoreProperties["keyPassword"] as String?
            storeFile = keystoreProperties["storeFile"]?.let { file(it) }
            storePassword = keystoreProperties["storePassword"] as String?
        }
    }

    buildTypes {
        release {
            // 没有正式 keystore 时不配置签名;对应 release 任务会在执行前明确失败。
            if (keystorePropertiesFile.exists()) {
                signingConfig = signingConfigs.getByName("release")
            }
            if (sideBySideRelease) applicationIdSuffix = ".release"
        }
    }
}

if (!keystorePropertiesFile.exists()) {
    tasks.matching { it.name == "assembleRelease" || it.name == "bundleRelease" }
        .configureEach {
            doFirst {
                throw GradleException(
                    "Missing android/key.properties; configure a release keystore before building a release APK.")
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
