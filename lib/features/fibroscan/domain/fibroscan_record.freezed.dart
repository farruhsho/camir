// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'fibroscan_record.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$FibroscanRecord {

 String get id;// Пациент из базы (если исследование привязано к карте); журнал допускает и
// разовые записи без карты — тогда patientId отсутствует, а ФИО вводится вручную.
 String? get patientId; String get fullName;// Год рождения (только год — дата рождения целиком в этом журнале не нужна).
 int get birthYear;// Дата исследования. Хранится строкой в ISO-формате `YYYY-MM-DD` (как во
// всех коллекциях); на экран выводится как ДД.ММ.ГГГГ.
 String get date;// Диагноз из справочника [kFibroscanDiagnoses].
 String get diagnosis;// LSM — жёсткость печени (Liver Stiffness Measurement), кПа. По нему через
// [stageForLsm] выводится стадия фиброза. Необязателен (старые записи и
// разовый учёт могут его не содержать).
 num? get lsm;// CAP — контролируемый параметр затухания (дБ/м). По нему через
// [gradeForCap] выводится степень стеатоза. Необязателен.
 num? get cap;// IQR/Med (%) — межквартильный размах, нормированный на медиану LSM; мера
// надёжности измерения жёсткости. Клинически валидным сканом печени обычно
// считают IQR/Med ≤ 30%. Необязателен (старые/разовые записи без него).
 num? get iqrMed;// Число валидных измерений (обычно прибор набирает 10). Косвенно отражает
// качество серии. Необязателен.
 int? get validMeasurements;// Когда запись создана (`created_at` из Firestore). Только для отображения в
// детальном просмотре — на запись не влияет (штампует репозиторий).
@FibroTimestampConverter() DateTime? get createdAt;
/// Create a copy of FibroscanRecord
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FibroscanRecordCopyWith<FibroscanRecord> get copyWith => _$FibroscanRecordCopyWithImpl<FibroscanRecord>(this as FibroscanRecord, _$identity);

  /// Serializes this FibroscanRecord to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FibroscanRecord&&(identical(other.id, id) || other.id == id)&&(identical(other.patientId, patientId) || other.patientId == patientId)&&(identical(other.fullName, fullName) || other.fullName == fullName)&&(identical(other.birthYear, birthYear) || other.birthYear == birthYear)&&(identical(other.date, date) || other.date == date)&&(identical(other.diagnosis, diagnosis) || other.diagnosis == diagnosis)&&(identical(other.lsm, lsm) || other.lsm == lsm)&&(identical(other.cap, cap) || other.cap == cap)&&(identical(other.iqrMed, iqrMed) || other.iqrMed == iqrMed)&&(identical(other.validMeasurements, validMeasurements) || other.validMeasurements == validMeasurements)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,patientId,fullName,birthYear,date,diagnosis,lsm,cap,iqrMed,validMeasurements,createdAt);

@override
String toString() {
  return 'FibroscanRecord(id: $id, patientId: $patientId, fullName: $fullName, birthYear: $birthYear, date: $date, diagnosis: $diagnosis, lsm: $lsm, cap: $cap, iqrMed: $iqrMed, validMeasurements: $validMeasurements, createdAt: $createdAt)';
}


}

/// @nodoc
abstract mixin class $FibroscanRecordCopyWith<$Res>  {
  factory $FibroscanRecordCopyWith(FibroscanRecord value, $Res Function(FibroscanRecord) _then) = _$FibroscanRecordCopyWithImpl;
@useResult
$Res call({
 String id, String? patientId, String fullName, int birthYear, String date, String diagnosis, num? lsm, num? cap, num? iqrMed, int? validMeasurements,@FibroTimestampConverter() DateTime? createdAt
});




}
/// @nodoc
class _$FibroscanRecordCopyWithImpl<$Res>
    implements $FibroscanRecordCopyWith<$Res> {
  _$FibroscanRecordCopyWithImpl(this._self, this._then);

  final FibroscanRecord _self;
  final $Res Function(FibroscanRecord) _then;

/// Create a copy of FibroscanRecord
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? patientId = freezed,Object? fullName = null,Object? birthYear = null,Object? date = null,Object? diagnosis = null,Object? lsm = freezed,Object? cap = freezed,Object? iqrMed = freezed,Object? validMeasurements = freezed,Object? createdAt = freezed,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,patientId: freezed == patientId ? _self.patientId : patientId // ignore: cast_nullable_to_non_nullable
as String?,fullName: null == fullName ? _self.fullName : fullName // ignore: cast_nullable_to_non_nullable
as String,birthYear: null == birthYear ? _self.birthYear : birthYear // ignore: cast_nullable_to_non_nullable
as int,date: null == date ? _self.date : date // ignore: cast_nullable_to_non_nullable
as String,diagnosis: null == diagnosis ? _self.diagnosis : diagnosis // ignore: cast_nullable_to_non_nullable
as String,lsm: freezed == lsm ? _self.lsm : lsm // ignore: cast_nullable_to_non_nullable
as num?,cap: freezed == cap ? _self.cap : cap // ignore: cast_nullable_to_non_nullable
as num?,iqrMed: freezed == iqrMed ? _self.iqrMed : iqrMed // ignore: cast_nullable_to_non_nullable
as num?,validMeasurements: freezed == validMeasurements ? _self.validMeasurements : validMeasurements // ignore: cast_nullable_to_non_nullable
as int?,createdAt: freezed == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}

}


/// Adds pattern-matching-related methods to [FibroscanRecord].
extension FibroscanRecordPatterns on FibroscanRecord {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _FibroscanRecord value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _FibroscanRecord() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _FibroscanRecord value)  $default,){
final _that = this;
switch (_that) {
case _FibroscanRecord():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _FibroscanRecord value)?  $default,){
final _that = this;
switch (_that) {
case _FibroscanRecord() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String? patientId,  String fullName,  int birthYear,  String date,  String diagnosis,  num? lsm,  num? cap,  num? iqrMed,  int? validMeasurements, @FibroTimestampConverter()  DateTime? createdAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _FibroscanRecord() when $default != null:
return $default(_that.id,_that.patientId,_that.fullName,_that.birthYear,_that.date,_that.diagnosis,_that.lsm,_that.cap,_that.iqrMed,_that.validMeasurements,_that.createdAt);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String? patientId,  String fullName,  int birthYear,  String date,  String diagnosis,  num? lsm,  num? cap,  num? iqrMed,  int? validMeasurements, @FibroTimestampConverter()  DateTime? createdAt)  $default,) {final _that = this;
switch (_that) {
case _FibroscanRecord():
return $default(_that.id,_that.patientId,_that.fullName,_that.birthYear,_that.date,_that.diagnosis,_that.lsm,_that.cap,_that.iqrMed,_that.validMeasurements,_that.createdAt);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String? patientId,  String fullName,  int birthYear,  String date,  String diagnosis,  num? lsm,  num? cap,  num? iqrMed,  int? validMeasurements, @FibroTimestampConverter()  DateTime? createdAt)?  $default,) {final _that = this;
switch (_that) {
case _FibroscanRecord() when $default != null:
return $default(_that.id,_that.patientId,_that.fullName,_that.birthYear,_that.date,_that.diagnosis,_that.lsm,_that.cap,_that.iqrMed,_that.validMeasurements,_that.createdAt);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _FibroscanRecord implements FibroscanRecord {
  const _FibroscanRecord({required this.id, this.patientId, required this.fullName, required this.birthYear, required this.date, required this.diagnosis, this.lsm, this.cap, this.iqrMed, this.validMeasurements, @FibroTimestampConverter() this.createdAt});
  factory _FibroscanRecord.fromJson(Map<String, dynamic> json) => _$FibroscanRecordFromJson(json);

@override final  String id;
// Пациент из базы (если исследование привязано к карте); журнал допускает и
// разовые записи без карты — тогда patientId отсутствует, а ФИО вводится вручную.
@override final  String? patientId;
@override final  String fullName;
// Год рождения (только год — дата рождения целиком в этом журнале не нужна).
@override final  int birthYear;
// Дата исследования. Хранится строкой в ISO-формате `YYYY-MM-DD` (как во
// всех коллекциях); на экран выводится как ДД.ММ.ГГГГ.
@override final  String date;
// Диагноз из справочника [kFibroscanDiagnoses].
@override final  String diagnosis;
// LSM — жёсткость печени (Liver Stiffness Measurement), кПа. По нему через
// [stageForLsm] выводится стадия фиброза. Необязателен (старые записи и
// разовый учёт могут его не содержать).
@override final  num? lsm;
// CAP — контролируемый параметр затухания (дБ/м). По нему через
// [gradeForCap] выводится степень стеатоза. Необязателен.
@override final  num? cap;
// IQR/Med (%) — межквартильный размах, нормированный на медиану LSM; мера
// надёжности измерения жёсткости. Клинически валидным сканом печени обычно
// считают IQR/Med ≤ 30%. Необязателен (старые/разовые записи без него).
@override final  num? iqrMed;
// Число валидных измерений (обычно прибор набирает 10). Косвенно отражает
// качество серии. Необязателен.
@override final  int? validMeasurements;
// Когда запись создана (`created_at` из Firestore). Только для отображения в
// детальном просмотре — на запись не влияет (штампует репозиторий).
@override@FibroTimestampConverter() final  DateTime? createdAt;

/// Create a copy of FibroscanRecord
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$FibroscanRecordCopyWith<_FibroscanRecord> get copyWith => __$FibroscanRecordCopyWithImpl<_FibroscanRecord>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$FibroscanRecordToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _FibroscanRecord&&(identical(other.id, id) || other.id == id)&&(identical(other.patientId, patientId) || other.patientId == patientId)&&(identical(other.fullName, fullName) || other.fullName == fullName)&&(identical(other.birthYear, birthYear) || other.birthYear == birthYear)&&(identical(other.date, date) || other.date == date)&&(identical(other.diagnosis, diagnosis) || other.diagnosis == diagnosis)&&(identical(other.lsm, lsm) || other.lsm == lsm)&&(identical(other.cap, cap) || other.cap == cap)&&(identical(other.iqrMed, iqrMed) || other.iqrMed == iqrMed)&&(identical(other.validMeasurements, validMeasurements) || other.validMeasurements == validMeasurements)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,patientId,fullName,birthYear,date,diagnosis,lsm,cap,iqrMed,validMeasurements,createdAt);

@override
String toString() {
  return 'FibroscanRecord(id: $id, patientId: $patientId, fullName: $fullName, birthYear: $birthYear, date: $date, diagnosis: $diagnosis, lsm: $lsm, cap: $cap, iqrMed: $iqrMed, validMeasurements: $validMeasurements, createdAt: $createdAt)';
}


}

/// @nodoc
abstract mixin class _$FibroscanRecordCopyWith<$Res> implements $FibroscanRecordCopyWith<$Res> {
  factory _$FibroscanRecordCopyWith(_FibroscanRecord value, $Res Function(_FibroscanRecord) _then) = __$FibroscanRecordCopyWithImpl;
@override @useResult
$Res call({
 String id, String? patientId, String fullName, int birthYear, String date, String diagnosis, num? lsm, num? cap, num? iqrMed, int? validMeasurements,@FibroTimestampConverter() DateTime? createdAt
});




}
/// @nodoc
class __$FibroscanRecordCopyWithImpl<$Res>
    implements _$FibroscanRecordCopyWith<$Res> {
  __$FibroscanRecordCopyWithImpl(this._self, this._then);

  final _FibroscanRecord _self;
  final $Res Function(_FibroscanRecord) _then;

/// Create a copy of FibroscanRecord
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? patientId = freezed,Object? fullName = null,Object? birthYear = null,Object? date = null,Object? diagnosis = null,Object? lsm = freezed,Object? cap = freezed,Object? iqrMed = freezed,Object? validMeasurements = freezed,Object? createdAt = freezed,}) {
  return _then(_FibroscanRecord(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,patientId: freezed == patientId ? _self.patientId : patientId // ignore: cast_nullable_to_non_nullable
as String?,fullName: null == fullName ? _self.fullName : fullName // ignore: cast_nullable_to_non_nullable
as String,birthYear: null == birthYear ? _self.birthYear : birthYear // ignore: cast_nullable_to_non_nullable
as int,date: null == date ? _self.date : date // ignore: cast_nullable_to_non_nullable
as String,diagnosis: null == diagnosis ? _self.diagnosis : diagnosis // ignore: cast_nullable_to_non_nullable
as String,lsm: freezed == lsm ? _self.lsm : lsm // ignore: cast_nullable_to_non_nullable
as num?,cap: freezed == cap ? _self.cap : cap // ignore: cast_nullable_to_non_nullable
as num?,iqrMed: freezed == iqrMed ? _self.iqrMed : iqrMed // ignore: cast_nullable_to_non_nullable
as num?,validMeasurements: freezed == validMeasurements ? _self.validMeasurements : validMeasurements // ignore: cast_nullable_to_non_nullable
as int?,createdAt: freezed == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}


}

// dart format on
