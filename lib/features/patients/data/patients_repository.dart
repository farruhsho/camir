import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/page.dart';
import '../../../core/utils/input_formatters.dart';
import '../domain/patient.dart';

final patientsRepositoryProvider = Provider<PatientsRepository>(
  (ref) => PatientsRepository(FirebaseFirestore.instance),
);

/// Картотека пациентов в **Firestore** (коллекция `patients`) — без бэкенда,
/// клиент пишет/читает напрямую (по образцу `analyses_repository`). Записи
/// отдаются свежими сверху (по `created_at`). Ключи документов — snake_case,
/// как ждёт [Patient]. № карты (`mrn`) выдаётся последовательно из счётчика
/// `counters/patients` в транзакции.
class PatientsRepository {
  PatientsRepository(this._db);

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('patients');

  /// Список пациентов, свежие сверху. [q] — необязательный поиск по ФИО / №
  /// карты / телефону (фильтр на клиенте, т.к. Firestore не умеет подстроку).
  ///
  /// Важно: при активном поиске нельзя ограничивать выборку только свежими
  /// [limit] записями — иначе `.contains(...)` «видит» лишь последних N карт и
  /// старые пациенты не находятся. Поэтому под поиск берём широкий рабочий набор
  /// (до 2000 карт), фильтруем его и лишь потом отдаём первые [limit] совпадений.
  /// Практический потолок — 2000 карт; при большем объёме нужен серверный
  /// префиксный поиск (документированный follow-up).
  Future<Page<Patient>> list({String? q, int limit = 200}) async {
    final needle = q?.trim().toLowerCase() ?? '';
    const kSearchScanCeiling = 2000;
    final fetchLimit = needle.isEmpty ? limit : kSearchScanCeiling;
    final snap = await _col
        .orderBy('created_at', descending: true)
        .limit(fetchLimit)
        .get();
    var patients = snap.docs
        .map((d) => Patient.fromMap({...d.data(), 'id': d.id}))
        .toList();
    if (needle.isNotEmpty) {
      patients = patients
          .where(
            (p) =>
                p.fullName.toLowerCase().contains(needle) ||
                p.mrn.toLowerCase().contains(needle) ||
                (p.phone ?? '').toLowerCase().contains(needle),
          )
          .take(limit)
          .toList();
    }
    return Page<Patient>(
      items: patients,
      total: patients.length,
      offset: 0,
      limit: limit,
    );
  }

  /// Точный поиск карты по нормализованному номеру `+996XXXXXXXXX`. Используется
  /// регистратурой (agent G) для выявления дублей при приёме. Возвращает `null`,
  /// если номер пустой/неполный либо карта с таким телефоном не найдена.
  Future<Patient?> findByPhone(String phone) async {
    final normalized = assembleUzPhone(extractUzPhoneLocal(phone));
    if (normalized == null) return null;
    final snap = await _col
        .where('phone', isEqualTo: normalized)
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    final d = snap.docs.first;
    return Patient.fromMap({...d.data(), 'id': d.id});
  }

  /// Одна карта по id документа.
  Future<Patient> byId(String id) async {
    final doc = await _col.doc(id).get();
    return Patient.fromMap({...?doc.data(), 'id': doc.id});
  }

  /// Следующий № карты из счётчика `counters/patients` (атомарно, транзакцией).
  Future<String> _nextMrn() async {
    final counter = _db.collection('counters').doc('patients');
    final seq = await _db.runTransaction<int>((tx) async {
      final snap = await tx.get(counter);
      final current = (snap.data()?['seq'] as num?)?.toInt() ?? 0;
      final next = current + 1;
      tx.set(counter, <String, dynamic>{'seq': next}, SetOptions(merge: true));
      return next;
    });
    return seq.toString().padLeft(5, '0');
  }

  /// Регистрирует пациента. Пустые необязательные поля не пишутся.
  Future<Patient> create({
    required String lastName,
    required String firstName,
    String? middleName,
    required int birthYear,
    String? phone,
    String? disease,
    String? referral,
    String? consultation,
  }) async {
    final mrn = await _nextMrn();
    final ref = await _col.add(<String, dynamic>{
      'mrn': mrn,
      'last_name': lastName.trim(),
      'first_name': firstName.trim(),
      if (_clean(middleName) != null) 'middle_name': _clean(middleName),
      'birth_year': birthYear,
      if (_clean(phone) != null) 'phone': _clean(phone),
      if (_clean(disease) != null) 'disease': _clean(disease),
      if (_clean(referral) != null) 'referral': _clean(referral),
      if (_clean(consultation) != null) 'consultation': _clean(consultation),
      'created_at': FieldValue.serverTimestamp(),
      'created_by': FirebaseAuth.instance.currentUser?.uid,
    });
    final doc = await ref.get();
    return Patient.fromMap({...?doc.data(), 'id': doc.id});
  }

  /// Обновляет карту (форма редактирования отдаёт полный набор полей; пустые
  /// значения очищают поле). № карты и дата регистрации не меняются.
  Future<Patient> update(
    String id, {
    required String lastName,
    required String firstName,
    String? middleName,
    required int birthYear,
    String? phone,
    String? disease,
    String? referral,
    String? consultation,
  }) async {
    await _col.doc(id).update(<String, dynamic>{
      'last_name': lastName.trim(),
      'first_name': firstName.trim(),
      'middle_name': _clean(middleName),
      'birth_year': birthYear,
      'phone': _clean(phone),
      'disease': _clean(disease),
      'referral': _clean(referral),
      'consultation': _clean(consultation),
      'updated_by': FirebaseAuth.instance.currentUser?.uid,
      'updated_at': FieldValue.serverTimestamp(),
    });
    return byId(id);
  }

  static String? _clean(String? v) {
    final t = v?.trim();
    return (t == null || t.isEmpty) ? null : t;
  }
}

/// Одна карта пациента по id (используется карточкой врача и историей визитов).
final patientByIdProvider = FutureProvider.autoDispose.family<Patient, String>(
  (ref, id) => ref.watch(patientsRepositoryProvider).byId(id),
);
