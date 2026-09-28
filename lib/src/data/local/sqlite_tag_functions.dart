import 'package:sqlite3/common.dart' show CommonDatabase;
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../tag/domain/tag_name.dart';

const tagNameValidFunctionName = 'doable_tag_name_valid_v1';
const tagNameKeyFunctionName = 'doable_tag_name_key_v1';

/// Регистрирует долговечные функции названия тега для сохраняемой схемы.
void registerTagNameFunctions(CommonDatabase database) {
  final sqliteDatabase = database as sqlite.Database;
  sqliteDatabase
    ..createFunction(
      functionName: tagNameValidFunctionName,
      argumentCount: const sqlite.AllowedArgumentCount(1),
      deterministic: true,
      directOnly: false,
      function: (arguments) =>
          _validatedTagName(arguments.single) == null ? 0 : 1,
    )
    ..createFunction(
      functionName: tagNameKeyFunctionName,
      argumentCount: const sqlite.AllowedArgumentCount(1),
      deterministic: true,
      directOnly: false,
      function: (arguments) => _validatedTagName(arguments.single)?.matchingKey,
    );
}

TagName? _validatedTagName(Object? value) {
  if (value is! String) return null;
  try {
    return TagName.fromStored(value);
  } on TagNameValidationException {
    return null;
  }
}
