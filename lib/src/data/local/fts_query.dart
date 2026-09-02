import 'package:drift/drift.dart';

/// Возвращает FTS5 phrase для уже проверенного ключа только как SQL-параметр.
Variable<String> literalFtsPhraseParameter(String verifiedSearchKey) {
  final escapedSearchKey = verifiedSearchKey.replaceAll('"', '""');
  return Variable.withString('"$escapedSearchKey"');
}
