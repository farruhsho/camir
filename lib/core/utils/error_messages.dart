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

  // Fallback: тип не распознан. На Flutter web ошибки Firebase иногда приходят
  // не типизированными (обёртка JS-Future «Dart exception thrown from converted
  // Future…»), поэтому распознаём известные коды/слова прямо в тексте, чтобы
  // сотрудник всё равно увидел понятное русское сообщение, а не англ. код.
  final raw = error.toString();
  final lower = raw.toLowerCase();
  if (lower.contains('permission-denied') ||
      lower.contains('insufficient permission')) {
    return 'Недостаточно прав. Проверьте роль сотрудника и правила доступа '
        'Firestore (см. README → Bootstrap).';
  }
  if (lower.contains('unauthenticated')) {
    return 'Сессия истекла. Войдите заново.';
  }
  if (lower.contains('unavailable') ||
      lower.contains('network') ||
      lower.contains('offline')) {
    return 'Нет связи с сервером. Проверьте интернет-соединение.';
  }
  if (lower.contains('failed-precondition') || lower.contains('index')) {
    return 'Операция временно недоступна: возможно, ещё строится индекс '
        'Firestore. Повторите чуть позже.';
  }
  if (lower.contains('not-found')) {
    return 'Запись не найдена (возможно, уже удалена).';
  }
  if (lower.contains('converted future')) {
    return 'Не удалось выполнить операцию. Проверьте доступ и соединение.';
  }

  // AuthException.toString() и прочие уже дают человеко-читаемый текст; срезаем
  // возможный технический префикс вида `Error: ` / `[plugin/code] `.
  final text = raw
      .replaceFirst(RegExp(r'^Error:\s*'), '')
      .replaceFirst(RegExp(r'^\[[^\]]+\]\s*'), '');
  return text.isEmpty ? 'Произошла ошибка. Повторите попытку.' : text;
}
