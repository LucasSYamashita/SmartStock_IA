plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    // se usa Firebase, mantenha:
    id("com.google.gms.google-services")
}

android {
    namespace = "com.smartstock.app"
    defaultConfig {
        applicationId = "com.smartstock.app" // tem que bater com o google-services.json
    }
    buildTypes {
        release {
            isMinifyEnabled = false // evita erro do shrinkResources
        }
        debug { isMinifyEnabled = false }
    }


    buildTypes {
        release {
            // Evita aquele erro do shrinkResources
            isMinifyEnabled = false
            // NÃO ative shrinkResources
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
        debug { isMinifyEnabled = false }
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
