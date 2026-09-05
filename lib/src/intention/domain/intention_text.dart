import 'package:characters/characters.dart';

enum IntentionTextField { title, description, titleFilter }

enum IntentionTextValidationReason { empty, tooLong, invalidUnicodeRepertoire }

final class IntentionTextValidationFailure {
  const IntentionTextValidationFailure({
    required this.field,
    required this.reason,
  });

  final IntentionTextField field;
  final IntentionTextValidationReason reason;
}

final class IntentionTextValidationException implements Exception {
  const IntentionTextValidationException(this.failure);

  final IntentionTextValidationFailure failure;
}

abstract final class IntentionText {
  static const int maxTitleLength = 255;
  static const int maxDescriptionLength = 4096;

  static const _highSurrogateStart = 0xd800;
  static const _highSurrogateEnd = 0xdbff;
  static const _lowSurrogateStart = 0xdc00;
  static const _lowSurrogateEnd = 0xdfff;

  static int countGraphemeClusters(String value) => value.characters.length;

  static void ensureValidUnicodeRepertoire(
    String value, {
    required IntentionTextField field,
  }) {
    for (var index = 0; index < value.length; index++) {
      final codeUnit = value.codeUnitAt(index);
      if (codeUnit == 0) {
        throw _invalidUnicodeRepertoire(field);
      }
      if (_isHighSurrogate(codeUnit)) {
        final isFollowedByLowSurrogate =
            index + 1 < value.length &&
            _isLowSurrogate(value.codeUnitAt(index + 1));
        if (!isFollowedByLowSurrogate) {
          throw _invalidUnicodeRepertoire(field);
        }
        index++;
      } else if (_isLowSurrogate(codeUnit)) {
        throw _invalidUnicodeRepertoire(field);
      }
    }
  }

  static String normalizeTitle(String value) {
    ensureValidUnicodeRepertoire(value, field: IntentionTextField.title);
    final normalized = value.trim();
    if (normalized.isEmpty) {
      throw const IntentionTextValidationException(
        IntentionTextValidationFailure(
          field: IntentionTextField.title,
          reason: IntentionTextValidationReason.empty,
        ),
      );
    }
    _ensureLength(normalized, maxTitleLength, IntentionTextField.title);
    return normalized;
  }

  static String? normalizeDescription(String value) {
    ensureValidUnicodeRepertoire(value, field: IntentionTextField.description);
    if (value.trim().isEmpty) {
      return null;
    }
    _ensureLength(value, maxDescriptionLength, IntentionTextField.description);
    return value;
  }

  static void _ensureLength(
    String value,
    int maximum,
    IntentionTextField field,
  ) {
    if (countGraphemeClusters(value) > maximum) {
      throw IntentionTextValidationException(
        IntentionTextValidationFailure(
          field: field,
          reason: IntentionTextValidationReason.tooLong,
        ),
      );
    }
  }

  static IntentionTextValidationException _invalidUnicodeRepertoire(
    IntentionTextField field,
  ) => IntentionTextValidationException(
    IntentionTextValidationFailure(
      field: field,
      reason: IntentionTextValidationReason.invalidUnicodeRepertoire,
    ),
  );

  static bool _isHighSurrogate(int codeUnit) =>
      codeUnit >= _highSurrogateStart && codeUnit <= _highSurrogateEnd;

  static bool _isLowSurrogate(int codeUnit) =>
      codeUnit >= _lowSurrogateStart && codeUnit <= _lowSurrogateEnd;
}
