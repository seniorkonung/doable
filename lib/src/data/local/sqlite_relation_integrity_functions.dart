import 'dart:convert';
import 'dart:typed_data';

import 'package:sqlite3/common.dart' show CommonDatabase;
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../intention/domain/intention_id.dart';
import '../../long_term_relation/domain/long_term_relation_description.dart';
import '../../long_term_relation/domain/long_term_relation_id.dart';

const relationIdIntegrityFunctionName = 'doable_relation_id_is_valid';
const intentionIdIntegrityFunctionName = 'doable_intention_id_is_valid';
const relationDescriptionIntegrityFunctionName =
    'doable_relation_description_is_valid';

/// Регистрирует чистые функции проверки читаемых полей связи.
///
/// Функции принимают BLOB, чтобы проверять исходные байты SQLite без
/// неявной замены недопустимого UTF-8 при преобразовании в Dart String.
/// Контракт типов аргументов закреплён API sqlite3:
/// https://pub.dev/documentation/sqlite3/3.5.2/sqlite3/SqliteArguments-class.html
void registerRelationIntegrityFunctions(CommonDatabase database) {
  final sqliteDatabase = database as sqlite.Database;
  sqliteDatabase
    ..createFunction(
      functionName: relationIdIntegrityFunctionName,
      argumentCount: const sqlite.AllowedArgumentCount(1),
      deterministic: true,
      function: (arguments) => _isValidRelationId(arguments.single),
    )
    ..createFunction(
      functionName: intentionIdIntegrityFunctionName,
      argumentCount: const sqlite.AllowedArgumentCount(1),
      deterministic: true,
      function: (arguments) => _isValidIntentionId(arguments.single),
    )
    ..createFunction(
      functionName: relationDescriptionIntegrityFunctionName,
      argumentCount: const sqlite.AllowedArgumentCount(1),
      deterministic: true,
      function: (arguments) => _isValidStoredDescription(arguments.single),
    );
}

int _isValidRelationId(Object? value) {
  final decoded = _decodeStrictUtf8(value);
  if (decoded == null) return 0;
  return LongTermRelationId.decode(decoded) is LongTermRelationIdDecodingSuccess
      ? 1
      : 0;
}

int _isValidIntentionId(Object? value) {
  final decoded = _decodeStrictUtf8(value);
  if (decoded == null) return 0;
  return IntentionId.decode(decoded) is IntentionIdDecodingSuccess ? 1 : 0;
}

int _isValidStoredDescription(Object? value) {
  final decoded = _decodeStrictUtf8(value);
  if (decoded == null) return 0;
  try {
    return LongTermRelationDescription.fromInput(decoded) == null ? 0 : 1;
  } on LongTermRelationTextValidationException {
    return 0;
  }
}

String? _decodeStrictUtf8(Object? value) {
  if (value is! Uint8List) return null;
  try {
    // Строгое декодирование без заменяющего символа:
    // https://api.dart.dev/dart-convert/Utf8Codec/decode.html
    return utf8.decode(value, allowMalformed: false);
  } on FormatException {
    return null;
  }
}
