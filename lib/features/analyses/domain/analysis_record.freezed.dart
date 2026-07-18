// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'analysis_record.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$AnalysisRecord {

 String get id; String? get patientId; String get fullName; int get birthYear; String? get phone; String get analysisType; String? get result; String get date;
/// Create a copy of AnalysisRecord
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AnalysisRecordCopyWith<AnalysisRecord> get copyWith => _$AnalysisRecordCopyWithImpl<AnalysisRecord>(this as AnalysisRecord, _$identity);

  /// Serializes this AnalysisRecord to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AnalysisRecord&&(identical(other.id, id) || other.id == id)&&(identical(other.patientId, patientId) || other.patientId == patientId)&&(identical(other.fullName, fullName) || other.fullName == fullName)&&(identical(other.birthYear, birthYear) || other.birthYear == birthYear)&&(identical(other.phone, phone) || other.phone == phone)&&(identical(other.analysisType, analysisType) || other.analysisType == analysisType)&&(identical(other.result, result) || other.result == result)&&(identical(other.date, date) || other.date == date));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,patientId,fullName,birthYear,phone,analysisType,result,date);

@override
String toString() {
  return 'AnalysisRecord(id: $id, patientId: $patientId, fullName: $fullName, birthYear: $birthYear, phone: $phone, analysisType: $analysisType, result: $result, date: $date)';
}


}

/// @nodoc
abstract mixin class $AnalysisRecordCopyWith<$Res>  {
  factory $AnalysisRecordCopyWith(AnalysisRecord value, $Res Function(AnalysisRecord) _then) = _$AnalysisRecordCopyWithImpl;
@useResult
$Res call({
 String id, String? patientId, String fullName, int birthYear, String? phone, String analysisType, String? result, String date
});




}
/// @nodoc
class _$AnalysisRecordCopyWithImpl<$Res>
    implements $AnalysisRecordCopyWith<$Res> {
  _$AnalysisRecordCopyWithImpl(this._self, this._then);

  final AnalysisRecord _self;
  final $Res Function(AnalysisRecord) _then;

/// Create a copy of AnalysisRecord
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? patientId = freezed,Object? fullName = null,Object? birthYear = null,Object? phone = freezed,Object? analysisType = null,Object? result = freezed,Object? date = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,patientId: freezed == patientId ? _self.patientId : patientId // ignore: cast_nullable_to_non_nullable
as String?,fullName: null == fullName ? _self.fullName : fullName // ignore: cast_nullable_to_non_nullable
as String,birthYear: null == birthYear ? _self.birthYear : birthYear // ignore: cast_nullable_to_non_nullable
as int,phone: freezed == phone ? _self.phone : phone // ignore: cast_nullable_to_non_nullable
as String?,analysisType: null == analysisType ? _self.analysisType : analysisType // ignore: cast_nullable_to_non_nullable
as String,result: freezed == result ? _self.result : result // ignore: cast_nullable_to_non_nullable
as String?,date: null == date ? _self.date : date // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [AnalysisRecord].
extension AnalysisRecordPatterns on AnalysisRecord {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AnalysisRecord value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AnalysisRecord() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AnalysisRecord value)  $default,){
final _that = this;
switch (_that) {
case _AnalysisRecord():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AnalysisRecord value)?  $default,){
final _that = this;
switch (_that) {
case _AnalysisRecord() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String? patientId,  String fullName,  int birthYear,  String? phone,  String analysisType,  String? result,  String date)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AnalysisRecord() when $default != null:
return $default(_that.id,_that.patientId,_that.fullName,_that.birthYear,_that.phone,_that.analysisType,_that.result,_that.date);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String? patientId,  String fullName,  int birthYear,  String? phone,  String analysisType,  String? result,  String date)  $default,) {final _that = this;
switch (_that) {
case _AnalysisRecord():
return $default(_that.id,_that.patientId,_that.fullName,_that.birthYear,_that.phone,_that.analysisType,_that.result,_that.date);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String? patientId,  String fullName,  int birthYear,  String? phone,  String analysisType,  String? result,  String date)?  $default,) {final _that = this;
switch (_that) {
case _AnalysisRecord() when $default != null:
return $default(_that.id,_that.patientId,_that.fullName,_that.birthYear,_that.phone,_that.analysisType,_that.result,_that.date);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _AnalysisRecord implements AnalysisRecord {
  const _AnalysisRecord({required this.id, this.patientId, required this.fullName, required this.birthYear, this.phone, required this.analysisType, this.result, required this.date});
  factory _AnalysisRecord.fromJson(Map<String, dynamic> json) => _$AnalysisRecordFromJson(json);

@override final  String id;
@override final  String? patientId;
@override final  String fullName;
@override final  int birthYear;
@override final  String? phone;
@override final  String analysisType;
@override final  String? result;
@override final  String date;

/// Create a copy of AnalysisRecord
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AnalysisRecordCopyWith<_AnalysisRecord> get copyWith => __$AnalysisRecordCopyWithImpl<_AnalysisRecord>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$AnalysisRecordToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _AnalysisRecord&&(identical(other.id, id) || other.id == id)&&(identical(other.patientId, patientId) || other.patientId == patientId)&&(identical(other.fullName, fullName) || other.fullName == fullName)&&(identical(other.birthYear, birthYear) || other.birthYear == birthYear)&&(identical(other.phone, phone) || other.phone == phone)&&(identical(other.analysisType, analysisType) || other.analysisType == analysisType)&&(identical(other.result, result) || other.result == result)&&(identical(other.date, date) || other.date == date));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,patientId,fullName,birthYear,phone,analysisType,result,date);

@override
String toString() {
  return 'AnalysisRecord(id: $id, patientId: $patientId, fullName: $fullName, birthYear: $birthYear, phone: $phone, analysisType: $analysisType, result: $result, date: $date)';
}


}

/// @nodoc
abstract mixin class _$AnalysisRecordCopyWith<$Res> implements $AnalysisRecordCopyWith<$Res> {
  factory _$AnalysisRecordCopyWith(_AnalysisRecord value, $Res Function(_AnalysisRecord) _then) = __$AnalysisRecordCopyWithImpl;
@override @useResult
$Res call({
 String id, String? patientId, String fullName, int birthYear, String? phone, String analysisType, String? result, String date
});




}
/// @nodoc
class __$AnalysisRecordCopyWithImpl<$Res>
    implements _$AnalysisRecordCopyWith<$Res> {
  __$AnalysisRecordCopyWithImpl(this._self, this._then);

  final _AnalysisRecord _self;
  final $Res Function(_AnalysisRecord) _then;

/// Create a copy of AnalysisRecord
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? patientId = freezed,Object? fullName = null,Object? birthYear = null,Object? phone = freezed,Object? analysisType = null,Object? result = freezed,Object? date = null,}) {
  return _then(_AnalysisRecord(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,patientId: freezed == patientId ? _self.patientId : patientId // ignore: cast_nullable_to_non_nullable
as String?,fullName: null == fullName ? _self.fullName : fullName // ignore: cast_nullable_to_non_nullable
as String,birthYear: null == birthYear ? _self.birthYear : birthYear // ignore: cast_nullable_to_non_nullable
as int,phone: freezed == phone ? _self.phone : phone // ignore: cast_nullable_to_non_nullable
as String?,analysisType: null == analysisType ? _self.analysisType : analysisType // ignore: cast_nullable_to_non_nullable
as String,result: freezed == result ? _self.result : result // ignore: cast_nullable_to_non_nullable
as String?,date: null == date ? _self.date : date // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
