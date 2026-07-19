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
/// Модель даты рождения хранит **полную дату** [birthDate] (когда она известна)
/// и сохраняет обратную совместимость со старым полем `birth_year`:
///  * [birthDate] — `DateTime?`, разбирается из ISO `birth_date` (`ГГГГ-ММ-ДД`);
///  * [birthYear] — производный год: `birthDate?.year ?? legacy birth_year`
///    (0, если неизвестен) — на него опираются денормализация визитов и поиск
///    по фиброскану;
///  * [age] — полных лет от [birthDate] до текущего момента (`null`, если дата
///    неизвестна);
///  * [birthDisplay] — человекочитаемая подпись: `ДД.ММ.ГГГГ` при полной дате,
///    иначе `г.р. ГГГГ`, либо пустая строка, если год неизвестен.
///
/// [toMap] всегда пишет `birth_year` (int) для обратной совместимости и
/// дополнительно `birth_date` (ISO) — когда полная дата известна. [fromMap]
/// читает `birth_date`, если он есть, иначе — устаревший `birth_year`.
class Patient {
  const Patient({
    required this.id,
    required this.mrn,
    required this.lastName,
    required this.firstName,
    this.middleName,
    int birthYear = 0,
    this.birthDate,
    this.phone,
    this.disease,
    this.referral,
    this.consultation,
    this.registeredAt,
  }) : _birthYear = birthYear;

  final String id;

  /// № карты — последовательный номер, сгенерированный счётчиком при создании.
  final String mrn;
  final String lastName;
  final String firstName;
  final String? middleName;

  /// Устаревший хранимый год рождения (`birth_year`). Используется как запасной
  /// источник для [birthYear], когда полная [birthDate] неизвестна. Не читать
  /// напрямую — брать производный геттер [birthYear].
  final int _birthYear;

  /// Полная дата рождения (`birth_date`, ISO `ГГГГ-ММ-ДД`) — `null`, если
  /// известен только год или дата не заполнена.
  final DateTime? birthDate;

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

  /// Год рождения: из полной даты, иначе — устаревший `birth_year` (0, если
  /// неизвестен). На него опираются денормализация визитов и поиск фиброскана.
  int get birthYear => birthDate?.year ?? _birthYear;

  /// Полных лет от [birthDate] до сегодняшнего дня (`null`, если дата неизвестна).
  int? get age {
    final d = birthDate;
    if (d == null) return null;
    final now = DateTime.now();
    var years = now.year - d.year;
    if (now.month < d.month || (now.month == d.month && now.day < d.day)) {
      years--;
    }
    return years < 0 ? 0 : years;
  }

  /// Человекочитаемая дата рождения: `ДД.ММ.ГГГГ` при полной дате, иначе
  /// `г.р. ГГГГ`; пустая строка, если год рождения неизвестен.
  String get birthDisplay {
    final d = birthDate;
    if (d != null) {
      final dd = d.day.toString().padLeft(2, '0');
      final mm = d.month.toString().padLeft(2, '0');
      final yyyy = d.year.toString().padLeft(4, '0');
      return '$dd.$mm.$yyyy';
    }
    final y = birthYear;
    return y > 0 ? 'г.р. $y' : '';
  }

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

  factory Patient.fromMap(Map<String, dynamic> map) {
    DateTime? readTs(dynamic v) {
      if (v is Timestamp) return v.toDate();
      if (v is DateTime) return v;
      if (v is String) return DateTime.tryParse(v);
      return null;
    }

    /// Полная дата рождения из `birth_date`: ISO-строка `ГГГГ-ММ-ДД`
    /// (или Timestamp/DateTime на всякий случай). Дату нормализуем до
    /// «календарной» (без времени/таймзоны).
    DateTime? readBirthDate(dynamic v) {
      DateTime? parsed;
      if (v is Timestamp) {
        parsed = v.toDate();
      } else if (v is DateTime) {
        parsed = v;
      } else if (v is String && v.trim().isNotEmpty) {
        parsed = DateTime.tryParse(v.trim());
      }
      if (parsed == null) return null;
      return DateTime(parsed.year, parsed.month, parsed.day);
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
      birthDate: readBirthDate(map['birth_date']),
      birthYear: readYear(map['birth_year']),
      phone: str(map['phone']),
      disease: str(map['disease']),
      referral: str(map['referral']),
      consultation: str(map['consultation']),
      registeredAt: readTs(map['created_at']),
    );
  }

  /// Поля для записи в Firestore (без `id`/`created_at` — их ставит репозиторий).
  ///
  /// `birth_year` пишется всегда (обратная совместимость с денормализацией
  /// визитов и поиском фиброскана), `birth_date` (ISO `ГГГГ-ММ-ДД`) — только
  /// когда известна полная дата.
  Map<String, dynamic> toMap() {
    final d = birthDate;
    return <String, dynamic>{
      'mrn': mrn,
      'last_name': lastName,
      'first_name': firstName,
      if (middleName != null && middleName!.isNotEmpty)
        'middle_name': middleName,
      'birth_year': birthYear,
      if (d != null)
        'birth_date':
            '${d.year.toString().padLeft(4, '0')}-'
            '${d.month.toString().padLeft(2, '0')}-'
            '${d.day.toString().padLeft(2, '0')}',
      if (phone != null && phone!.isNotEmpty) 'phone': phone,
      if (disease != null && disease!.isNotEmpty) 'disease': disease,
      if (referral != null && referral!.isNotEmpty) 'referral': referral,
      if (consultation != null && consultation!.isNotEmpty)
        'consultation': consultation,
    };
  }
}
