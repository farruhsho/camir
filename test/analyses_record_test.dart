// Unit tests for [AnalysisRecord] JSON mapping (snake_case Firestore keys →
// freezed model). These pin the contract the analyses repository relies on and
// document *why* per-document parsing is wrapped in try/catch: the generated
// hard casts throw on a malformed document, which would otherwise crash the
// whole journal instead of skipping one bad record.
import 'package:flutter_test/flutter_test.dart';
import 'package:cadmir/features/analyses/domain/analysis_record.dart';

void main() {
  group('AnalysisRecord.fromJson', () {
    test('разбирает корректный документ из картотеки', () {
      final r = AnalysisRecord.fromJson(<String, dynamic>{
        'id': 'abc',
        'patient_id': 'p1',
        'full_name': 'Иванов Иван',
        'birth_year': 1990,
        'phone': '+996700123456',
        'analysis_type': 'ОАК',
        'result': 'норма',
        'date': '2026-07-18',
      });
      expect(r.id, 'abc');
      expect(r.patientId, 'p1');
      expect(r.fullName, 'Иванов Иван');
      expect(r.birthYear, 1990);
      expect(r.phone, '+996700123456');
      expect(r.analysisType, 'ОАК');
      expect(r.result, 'норма');
      expect(r.date, '2026-07-18');
    });

    test(
      'отсутствующие необязательные поля → null (ручной ввод без результата)',
      () {
        final r = AnalysisRecord.fromJson(<String, dynamic>{
          'id': 'x',
          'full_name': 'Петров Пётр',
          'birth_year': 1985,
          'analysis_type': 'АЛТ',
          'date': '2026-01-01',
        });
        expect(r.patientId, isNull);
        expect(r.phone, isNull);
        expect(r.result, isNull); // соответствует чипу «результат ожидается»
      },
    );

    test('birth_year как num (double из Firestore) приводится к int', () {
      final r = AnalysisRecord.fromJson(<String, dynamic>{
        'id': 'x',
        'full_name': 'Сидоров',
        'birth_year': 1975.0,
        'analysis_type': 'ОАМ',
        'date': '2026-02-02',
      });
      expect(r.birthYear, 1975);
    });

    test('битый документ (нет обязательного full_name) бросает — репозиторий '
        'ловит это и пропускает запись, а не роняет весь список', () {
      expect(
        () => AnalysisRecord.fromJson(<String, dynamic>{
          'id': 'bad',
          'birth_year': 2000,
          'analysis_type': 'ОАК',
          'date': '2026-03-03',
        }),
        throwsA(anything),
      );
    });
  });
}
