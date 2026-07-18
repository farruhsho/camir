plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    // ВНИМАНИЕ (go-live): продовый applicationId «Цадмир» — kg.cadmir.app.
    // Менять его нужно ВМЕСТЕ с регистрацией приложения в Firebase console и
    // повторным `flutterfire configure` (перегенерирует google-services.json /
    // firebase_options.dart под новый пакет) + переименованием package
    // MainActivity.kt. Пока google-services.json содержит com.example.cadmir,
    // поэтому здесь оставлен com.example.cadmir, иначе Android-сборка падает на
    // проверке google-services (нет клиента под пакет).
    namespace = "com.example.cadmir"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // Итоговый идентификатор приложения «Цадмир» в сторах/на устройстве:
        // на go-live сменить на kg.cadmir.app (см. комментарий у namespace).
        applicationId = "com.example.cadmir"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // ВНИМАНИЕ (deferred): для РЕЛИЗА нужен настоящий signing config +
            // keystore (.jks) — сгенерируйте его (`keytool -genkey ...`), заведите
            // android/key.properties (уже в .gitignore) и создайте
            // signingConfigs.release из него. Ключ/пароли в репозиторий НЕ
            // коммитить. Сейчас release подписывается ОТЛАДОЧНЫМ ключом только
            // чтобы `flutter run --release` работал локально — такой .apk/.aab
            // НЕЛЬЗЯ публиковать (несбыточный/непубликуемый билд).
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}
