import 'package:characters/characters.dart';

import '../../shared/domain/unicode_default_case_folding_17.dart';
import '../../shared/domain/unicode_text.dart';

enum TagNameFailureReason {
  invalidUnicodeRepertoire,
  empty,
  tooLong,
  nonCanonical,
}

final class TagNameValidationException implements Exception {
  const TagNameValidationException(this.reason);

  final TagNameFailureReason reason;
}

final class TagName {
  const TagName._(this.value);

  static const int maxGraphemeClusters = 255;

  static TagName fromInput(String input) {
    _ensureValidUnicode(input);
    final value = trimSurroundingWhitespace(input);
    _ensureValidLength(value);
    return TagName._(value);
  }

  static TagName fromStored(String stored) {
    _ensureValidUnicode(stored);
    final canonical = trimSurroundingWhitespace(stored);
    _ensureValidLength(canonical);
    if (canonical != stored) {
      throw const TagNameValidationException(TagNameFailureReason.nonCanonical);
    }
    return TagName._(stored);
  }

  /// Единое правило окружающих пробелов для названия и поиска по названиям.
  static String trimSurroundingWhitespace(String input) => input.trim();

  static void _ensureValidUnicode(String value) {
    try {
      UnicodeText.ensureValidScalarValuesWithoutNul(value);
    } on InvalidUnicodeTextException {
      throw const TagNameValidationException(
        TagNameFailureReason.invalidUnicodeRepertoire,
      );
    }
  }

  static void _ensureValidLength(String value) {
    if (value.isEmpty) {
      throw const TagNameValidationException(TagNameFailureReason.empty);
    }
    if (value.characters.length > maxGraphemeClusters) {
      throw const TagNameValidationException(TagNameFailureReason.tooLong);
    }
  }

  final String value;

  String get matchingKey => UnicodeDefaultCaseFolding17.fold(value);

  @override
  bool operator ==(Object other) => other is TagName && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'TagName';
}
