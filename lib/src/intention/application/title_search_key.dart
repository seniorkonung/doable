import 'package:doable/src/shared/domain/unicode_default_case_folding_17.dart';

const unicodeDefaultCaseFoldingVersion = UnicodeDefaultCaseFolding17.version;

/// Строит поисковый ключ названия намерения.
String titleSearchKey(String value) => UnicodeDefaultCaseFolding17.fold(value);
