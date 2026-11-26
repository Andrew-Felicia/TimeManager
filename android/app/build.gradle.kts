import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.plugin.compose")
}

val updateSigningPropertiesFile = rootProject.file("signing.properties")
val updateSigningProperties = Properties().apply {
    if (updateSigningPropertiesFile.exists()) {
        updateSigningPropertiesFile.inputStream().use(::load)
    }
}

android {
    namespace = "app.flowtime.android"
    compileSdk = 37

    defaultConfig {
        applicationId = "app.flowtime.android"
        minSdk = 26
        targetSdk = 37
        versionCode = 4
        versionName = "1.0.2"
    }

    if (updateSigningPropertiesFile.exists()) {
        signingConfigs {
            create("flowtimeUpdate") {
                storeFile = rootProject.file(updateSigningProperties.getProperty("storeFile"))
                storePassword = updateSigningProperties.getProperty("storePassword")
                keyAlias = updateSigningProperties.getProperty("keyAlias")
                keyPassword = updateSigningProperties.getProperty("keyPassword")
            }
        }
        buildTypes {
            getByName("debug") {
                signingConfig = signingConfigs.getByName("flowtimeUpdate")
            }
        }
    }

    buildFeatures {
        compose = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    packaging {
        resources.excludes += "/META-INF/{AL2.0,LGPL2.1}"
    }
}

dependencies {
    val composeBom = platform("androidx.compose:compose-bom:2026.09.00")
    implementation(composeBom)
    androidTestImplementation(composeBom)

    implementation("androidx.activity:activity-compose:1.13.0")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-extended")
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-tooling-preview")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.11.1")
    implementation("androidx.lifecycle:lifecycle-viewmodel-ktx:2.11.1")
    debugImplementation("androidx.compose.ui:ui-tooling")
}
