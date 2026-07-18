import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Firebase (проект cadmir-erp, регион europe-west1) — единственный бэкенд
  // (Firestore + Auth), своего сервера нет. Инициализация строго best-effort:
  // клиника должна работать и без сети до Firebase — ошибка логируется,
  // приложение стартует в любом случае.
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    debugPrint('Firebase init skipped: $e');
  }
  runApp(const ProviderScope(child: CadmirApp()));
}
