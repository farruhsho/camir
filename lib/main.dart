import 'package:cloud_firestore/cloud_firestore.dart';
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
    // ЛОКАЛЬНЫЙ КЭШ FIRESTORE (офлайн-персистентность). Устанавливается ДО
    // первого обращения к Firestore. Чтения обслуживаются из локального кэша
    // (IndexedDB на web, SQLite на моб/десктоп) — мгновенно и без сети, а
    // синхронизация идёт в фоне. Это убирает «долгую загрузку»/подвисания при
    // повторных заходах на экраны и даёт работу офлайн.
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    );
  } catch (e) {
    debugPrint('Firebase init skipped: $e');
  }
  runApp(const ProviderScope(child: CadmirApp()));
}
