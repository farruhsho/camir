import 'package:flutter/material.dart';

/// Универсальный диалог подтверждения действия.
///
/// Возвращает `true`, только если пользователь нажал кнопку подтверждения;
/// закрытие по «Отмена», по фону или системной кнопкой «назад» → `false`.
///
/// Используется перед необратимыми операциями (удаление, аннулирование,
/// смена статуса и т.п.). При [danger] = true кнопка подтверждения красная.
///
/// Пример:
/// ```dart
/// if (await confirmDialog(context,
///     title: 'Удалить пациента?',
///     message: 'Карта и связанные записи будут удалены.')) {
///   await repo.delete(id);
/// }
/// ```
Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Удалить',
  bool danger = true,
}) async {
  final scheme = Theme.of(context).colorScheme;
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      final confirmButton = danger
          ? FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: scheme.error,
                foregroundColor: scheme.onError,
              ),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(confirmLabel),
            )
          : FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(confirmLabel),
            );
      return AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Отмена'),
          ),
          confirmButton,
        ],
      );
    },
  );
  return result ?? false;
}
