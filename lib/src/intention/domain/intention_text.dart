import 'package:characters/characters.dart';

enum IntentionTextValidationFailure {
  emptyTitle,
  titleTooLong,
  descriptionTooLong,
}

final class IntentionTextValidationException implements Exception {
  const IntentionTextValidationException(this.failure);

  final IntentionTextValidationFailure failure;
}

abstract final class IntentionText {
  static const int maxTitleLength = 255;
  static const int maxDescriptionLength = 4096;

  static String normalizeTitle(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      throw const IntentionTextValidationException(
        IntentionTextValidationFailure.emptyTitle,
      );
    }
    _ensureLength(
      normalized,
      maxTitleLength,
      IntentionTextValidationFailure.titleTooLong,
    );
    return normalized;
  }

  static String? normalizeDescription(String value) {
    if (value.trim().isEmpty) {
      return null;
    }
    _ensureLength(
      value,
      maxDescriptionLength,
      IntentionTextValidationFailure.descriptionTooLong,
    );
    return value;
  }

  static void _ensureLength(
    String value,
    int maximum,
    IntentionTextValidationFailure failure,
  ) {
    if (value.characters.length > maximum) {
      throw IntentionTextValidationException(failure);
    }
  }
}
