import 'package:characters/characters.dart';

import '../../shared/domain/unicode_text.dart';

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

  static int countGraphemeClusters(String value) => value.characters.length;

  static void ensureValidUnicodeRepertoire(
    String value, {
    required IntentionTextField field,
  }) {
    try {
      UnicodeText.ensureValidScalarValuesWithoutNul(value);
    } on InvalidUnicodeTextException {
      throw _invalidUnicodeRepertoire(field);
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
}
