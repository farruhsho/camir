import 'package:firebase_auth/firebase_auth.dart';

/// Переводит технические исключения (Firebase Auth / Firestore и пр.) в понятное
/// пользователю русское сообщение. Единая точка: все catch-блоки экранов и
/// [AsyncValueWidget] прогоняют ошибку через [friendlyError], чтобы сотрудник
/// клиники «Цадмир» никогда не видел англоязычные коды вида
/// `[cloud_firestore/permission-denied] ...`.
///
/// [AuthException] (RU-текст уже в `toString()`) и любые уже-человеческие строки
/// проходят как есть.
String friendlyError(Object? error) {
  if (error == null) return 'Произошла неизвестная ошибка.';

  if (error is FirebaseAuthException) {
    return switch (error.code) {
      'invalid-email' => 'Некорректный email.',
      'user-disabled' => 'Учётная запись отключена. Обратитесь к администратору.',
      'user-not-found' ||
      'wrong-password' ||
      'invalid-credential' => 'Неверный email или пароль.',
      'email-already-in-use' => 'Этот email уже занят.',
      'weak-password' => 'Слишком простой пароль (минимум 6 символов).',
      'operation-not-allowed' =>
        'Вход по email/паролю отключён в настройках Firebase.',
      'too-many-requests' => 'Слишком много попыток. Повторите позже.',
      'network-request-failed' =>
        'Нет связи с сервером. Проверьте интернет-соединение.',
      _ => error.message ?? 'Ошибка аутентификации (${error.code}).',
    };
  }

  if (error is FirebaseException) {
    return switch (error.code) {
      'permission-denied' => 'Недостаточно прав для этого действия.',
      'unavailable' || 'network-request-failed' =>
        'Нет связи с сервером. Проверьте интернет-соединение.',
      'not-found' => 'Запись не найдена (возможно, уже удалена).',
      'already-exists' => 'Такая запись уже существует.',
      'deadline-exceeded' => 'Сервер не ответил вовремя. Повторите попытку.',
      'resource-exhausted' => 'Превышен лимит запросов. Повторите позже.',
      'failed-precondition' =>
        'Операция невозможна в текущем состоянии данных.',
      'unauthenticated' => 'Сессия истекла. Войдите заново.',
      _ => error.message ?? 'Ошибка сервера (${error.code}).',
    };
  }

  // AuthException.toString() и прочие уже дают человеко-читаемый текст; на всякий
  // случай срезаем возможный технический префикс вида `[plugin/code] `.
  final text = error.toString().replaceFirst(RegExp(r'^\[[^\]]+\]\s*'), '');
  return text.isEmpty ? 'Произошла ошибка. Повторите попытку.' : text;
}
