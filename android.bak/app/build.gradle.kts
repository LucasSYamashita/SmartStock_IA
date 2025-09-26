import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("com.google.gms.google-services")
}

// Lê o caminho do SDK do Flutter
val localProperties = Properties()
val localPropertiesFile = rootProject.file("local.properties")
if (localPropertiesFile.exists()) {
    localProperties.load(FileInputStream(localPropertiesFile))
}
val flutterRoot = localProperties.getProperty("flutter.sdk")
require(!flutterRoot.isNullOrBlank()) { "flutter.sdk não encontrado em local.properties" }

// Integração clássica com Flutter (sem plugin loader)
apply(from = "$flutterRoot/packages/flutter_tools/gradle/flutter.gradle")

android {
    namespace = "com.smartstock.app"
    compileSdk = flutter.compileSdkVersion

    defaultConfig {
        applicationId = "com.smartstock.app"   // <- deve bater com o google-services.json
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // Evita o erro do shrinkResources
            isMinifyEnabled = false
            // NÃO habilite shrinkResources aqui
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
        debug {
            isMinifyEnabled = false
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }
}

flutter {
    source = "../.."
}
