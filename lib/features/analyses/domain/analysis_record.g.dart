// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'analysis_record.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_AnalysisRecord _$AnalysisRecordFromJson(Map<String, dynamic> json) =>
    _AnalysisRecord(
      id: json['id'] as String,
      patientId: json['patient_id'] as String?,
      fullName: json['full_name'] as String,
      birthYear: (json['birth_year'] as num).toInt(),
      phone: json['phone'] as String?,
      analysisType: json['analysis_type'] as String,
      result: json['result'] as String?,
      date: json['date'] as String,
    );

Map<String, dynamic> _$AnalysisRecordToJson(_AnalysisRecord instance) =>
    <String, dynamic>{
      'id': instance.id,
      'patient_id': instance.patientId,
      'full_name': instance.fullName,
      'birth_year': instance.birthYear,
      'phone': instance.phone,
      'analysis_type': instance.analysisType,
      'result': instance.result,
      'date': instance.date,
    };
