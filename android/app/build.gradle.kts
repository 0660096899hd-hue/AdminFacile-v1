import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val releaseProperties = Properties()
val releasePropertiesFile = rootProject.file("key.properties")
val releaseSigningConfigured = releasePropertiesFile.exists()
if (releaseSigningConfigured) {
    releasePropertiesFile.inputStream().use { releaseProperties.load(it) }
}

android {
    namespace = "fr.adminfacile.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    flavorDimensions += "country"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildFeatures {
        resValues = true
    }

    defaultConfig {
        // Le package historique reste la valeur de repli et celle du flavor
        // France afin de préserver les mises à jour Google Play existantes.
        applicationId = "fr.adminfacile.app"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    productFlavors {
        create("france") {
            dimension = "country"
            applicationId = "fr.adminfacile.app"
            resValue("string", "app_name", "AdminFacile")
        }
        create("spain") {
            dimension = "country"
            applicationId = "es.adminfacile.app"
            resValue("string", "app_name", "AdminFácil")
        }
        create("italy") {
            dimension = "country"
            applicationId = "it.adminfacile.app"
            resValue("string", "app_name", "Amministrazione Facile")
        }
        create("morocco") {
            dimension = "country"
            applicationId = "ma.adminfacile.app"
            resValue("string", "app_name", "AdminFacile Maroc")
        }
    }

    signingConfigs {
        if (releaseSigningConfigured) {
            create("release") {
                keyAlias = releaseProperties.getProperty("keyAlias")
                keyPassword = releaseProperties.getProperty("keyPassword")
                storeFile = file(releaseProperties.getProperty("storeFile"))
                storePassword = releaseProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            // Sans key.properties, le bundle reste volontairement non signé et
            // ne doit pas être envoyé sur Google Play.
            signingConfig = if (releaseSigningConfigured) {
                signingConfigs.getByName("release")
            } else {
                null
            }
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
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

dependencies {
    implementation("com.google.android.gms:play-services-mlkit-document-scanner:16.0.0")
}
