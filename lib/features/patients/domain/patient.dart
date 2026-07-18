import 'package:cloud_firestore/cloud_firestore.dart';

/// Направления пациента при регистрации (куда его дальше отправить).
const String kReferralFibroscan = 'fibroscan';
const String kReferralAnalyses = 'analyses';
const String kReferralConsult = 'consultation';

/// Значение направления → русская подпись (выпадашка регистратуры и карточка).
const Map<String, String> kReferralLabels = <String, String>{
  kReferralFibroscan: 'Фиброскан',
  kReferralAnalyses: 'Анализы',
  kReferralConsult: 'Консультация',
};

/// Карточка пациента гематологического центра «Цадмир».
///
/// Простой immutable-класс с [fromMap]/[toMap] под коллекцию Firestore
/// `patients` — без Dio/бэкенда. Ключи документа хранятся в snake_case.
///
/// Помимо профильных полей (ФИО, год рождения, телефон, вид болезни,
/// направление, заметка консультации) отдаёт один производный геттер
/// совместимости — [birthDate] (`ГГГГ-01-01`), из которого экран «Анализы»
/// берёт год рождения при предзаполнении формы. Отдельных хранимых полей
/// совместимости у карты нет.
class Patient {
  const Patient({
    required this.id,
    required this.mrn,
    required this.lastName,
    required this.firstName,
    this.middleName,
    required this.birthYear,
    this.phone,
    this.disease,
    this.referral,
    this.consultation,
    this.registeredAt,
  });

  final String id;

  /// № карты — последовательный номер, сгенерированный счётчиком при создании.
  final String mrn;
  final String lastName;
  final String firstName;
  final String? middleName;

  /// Год рождения (только год; полную дату регистратура «Цадмир» не ведёт).
  final int birthYear;

  /// Телефон в формате `+996XXXXXXXXX`.
  final String? phone;

  /// Вид болезни (первичное направление гематолога).
  final String? disease;

  /// Направление: [kReferralFibroscan] / [kReferralAnalyses] / [kReferralConsult].
  final String? referral;

  /// Заметка консультации, оставленная при регистрации.
  final String? consultation;

  /// Когда пациент зарегистрирован (`created_at` из Firestore).
  final DateTime? registeredAt;

  /// ФИО одной строкой «Фамилия Имя Отчество» (пустые части опускаются).
  String get fullName => <String>[
    lastName,
    firstName,
    ?middleName,
  ].where((p) => p.trim().isNotEmpty).join(' ');

  /// Инициалы для аватара (Фамилия + Имя).
  String get initials {
    final a = lastName.isNotEmpty ? lastName[0] : '';
    final b = firstName.isNotEmpty ? firstName[0] : '';
    return '$a$b'.toUpperCase();
  }

  /// Русская подпись направления (или `null`, если не задано).
  String? get referralLabel =>
      referral == null ? null : (kReferralLabels[referral] ?? referral);

  /// Дата рождения в ISO (`ГГГГ-01-01`) — совместимость для экрана «Анализы»,
  /// который ожидает строку и достаёт из неё год при предзаполнении формы.
  String? get birthDate =>
      birthYear > 0 ? '${birthYear.toString().padLeft(4, '0')}-01-01' : null;

  factory Patient.fromMap(Map<String, dynamic> map) {
    DateTime? readTs(dynamic v) {
      if (v is Timestamp) return v.toDate();
      if (v is DateTime) return v;
      if (v is String) return DateTime.tryParse(v);
      return null;
    }

    int readYear(dynamic v) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse('${v ?? ''}') ?? 0;
    }

    String? str(dynamic v) {
      final s = v?.toString();
      return (s == null || s.isEmpty) ? null : s;
    }

    return Patient(
      id: map['id']?.toString() ?? '',
      mrn: map['mrn']?.toString() ?? '',
      lastName: map['last_name']?.toString() ?? '',
      firstName: map['first_name']?.toString() ?? '',
      middleName: str(map['middle_name']),
      birthYear: readYear(map['birth_year']),
      phone: str(map['phone']),
      disease: str(map['disease']),
      referral: str(map['referral']),
      consultation: str(map['consultation']),
      registeredAt: readTs(map['created_at']),
    );
  }

  /// Поля для записи в Firestore (без `id`/`created_at` — их ставит репозиторий).
  Map<String, dynamic> toMap() => <String, dynamic>{
    'mrn': mrn,
    'last_name': lastName,
    'first_name': firstName,
    if (middleName != null && middleName!.isNotEmpty) 'middle_name': middleName,
    'birth_year': birthYear,
    if (phone != null && phone!.isNotEmpty) 'phone': phone,
    if (disease != null && disease!.isNotEmpty) 'disease': disease,
    if (referral != null && referral!.isNotEmpty) 'referral': referral,
    if (consultation != null && consultation!.isNotEmpty)
      'consultation': consultation,
  };
}
