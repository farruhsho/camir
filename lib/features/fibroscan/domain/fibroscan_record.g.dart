// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'fibroscan_record.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_FibroscanRecord _$FibroscanRecordFromJson(Map<String, dynamic> json) =>
    _FibroscanRecord(
      id: json['id'] as String,
      patientId: json['patient_id'] as String?,
      fullName: json['full_name'] as String,
      birthYear: (json['birth_year'] as num).toInt(),
      date: json['date'] as String,
      diagnosis: json['diagnosis'] as String,
    );

Map<String, dynamic> _$FibroscanRecordToJson(_FibroscanRecord instance) =>
    <String, dynamic>{
      'id': instance.id,
      'patient_id': instance.patientId,
      'full_name': instance.fullName,
      'birth_year': instance.birthYear,
      'date': instance.date,
      'diagnosis': instance.diagnosis,
    };
