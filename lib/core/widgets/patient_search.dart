import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/patients/data/patients_repository.dart';
import '../../features/patients/domain/patient.dart';
import '../theme/app_colors.dart';
import 'koz_widgets.dart';

/// Единый переиспользуемый выбор пациента из картотеки — «поиск перед созданием».
///
/// Открывает модальный диалог, который ищет по коллекции `patients`
/// (`patientsRepository.list(q, limit: 8)`) с дебаунсом 350 мс по ФИО / № карты
/// / телефону и возвращает выбранного [Patient] либо `null`, если пользователь
/// закрыл окно без выбора.
///
/// Пример:
/// ```dart
/// final p = await pickPatient(context);
/// if (p != null) { /* подставить ФИО, дату рождения, телефон */ }
/// ```
Future<Patient?> pickPatient(BuildContext context) {
  return showDialog<Patient>(
    context: context,
    builder: (_) => const _PatientSearchDialog(),
  );
}

class _PatientSearchDialog extends ConsumerStatefulWidget {
  const _PatientSearchDialog();

  @override
  ConsumerState<_PatientSearchDialog> createState() =>
      _PatientSearchDialogState();
}

class _PatientSearchDialogState extends ConsumerState<_PatientSearchDialog> {
  final _q = TextEditingController();
  List<Patient> _results = const <Patient>[];
  bool _loading = false;
  bool _searched = false;
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _q.dispose();
    super.dispose();
  }

  // Дебаунс: поиск бьёт по картотеке широким запросом, поэтому не на каждый
  // символ, а через 350 мс после остановки ввода.
  void _onChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => _search(q));
  }

  Future<void> _search(String q) async {
    final needle = q.trim();
    if (needle.isEmpty) {
      setState(() {
        _results = const <Patient>[];
        _searched = false;
        _loading = false;
      });
      return;
    }
    setState(() => _loading = true);
    try {
      final page = await ref
          .read(patientsRepositoryProvider)
          .list(q: needle, limit: 8);
      if (mounted) {
        setState(() {
          _results = page.items;
          _searched = true;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _results = const <Patient>[];
          _searched = true;
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Найти пациента'),
      content: SizedBox(
        width: 380,
        height: 380,
        child: Column(
          children: [
            TextField(
              controller: _q,
              autofocus: true,
              textInputAction: TextInputAction.search,
              decoration: const InputDecoration(
                labelText: 'ФИО / № карты / телефон',
                isDense: true,
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: _onChanged,
              onSubmitted: _search,
            ),
            const SizedBox(height: 8),
            Expanded(child: _body()),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Закрыть'),
        ),
      ],
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_results.isEmpty) {
      return Center(
        child: Text(
          _searched ? 'Ничего не найдено' : 'Введите запрос для поиска',
          style: const TextStyle(color: AppColors.sub),
        ),
      );
    }
    return ListView.separated(
      itemCount: _results.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final p = _results[i];
        final sub = <String>[
          '№ ${p.mrn}',
          if (p.birthDisplay.isNotEmpty) p.birthDisplay,
          if (p.phone != null && p.phone!.isNotEmpty) p.phone!,
        ].join('  ·  ');
        return ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: InitialsAvatar(p.initials, size: 34),
          title: Text(p.fullName),
          subtitle: Text(sub),
          onTap: () => Navigator.pop(context, p),
        );
      },
    );
  }
}
