import 'package:characters/characters.dart';

import '../../shared/domain/unicode_text.dart';

enum DailyChoiceDescriptionField { description }

enum DailyChoiceDescriptionValidationReason {
  absent,
  tooLong,
  invalidUnicodeRepertoire,
}

final class DailyChoiceDescriptionValidationFailure {
  const DailyChoiceDescriptionValidationFailure({
    required this.field,
    required this.reason,
  });

  final DailyChoiceDescriptionField field;
  final DailyChoiceDescriptionValidationReason reason;
}

final class DailyChoiceDescriptionValidationException implements Exception {
  const DailyChoiceDescriptionValidationException(this.failure);

  final DailyChoiceDescriptionValidationFailure failure;
}

final class DailyChoiceDescription {
  const DailyChoiceDescription._(this.value);

  static const int maxGraphemeClusters = 4096;

  final String value;

  static DailyChoiceDescription? fromInput(String value) {
    if (_validate(value) == null) {
      return null;
    }
    return DailyChoiceDescription._(value);
  }

  static DailyChoiceDescription fromStored(String value) {
    if (_validate(value) == null) {
      throw const DailyChoiceDescriptionValidationException(
        DailyChoiceDescriptionValidationFailure(
          field: DailyChoiceDescriptionField.description,
          reason: DailyChoiceDescriptionValidationReason.absent,
        ),
      );
    }
    return DailyChoiceDescription._(value);
  }

  static String? _validate(String value) {
    try {
      UnicodeText.ensureValidScalarValuesWithoutNul(value);
    } on InvalidUnicodeTextException {
      throw const DailyChoiceDescriptionValidationException(
        DailyChoiceDescriptionValidationFailure(
          field: DailyChoiceDescriptionField.description,
          reason:
              DailyChoiceDescriptionValidationReason.invalidUnicodeRepertoire,
        ),
      );
    }
    if (value.trim().isEmpty) {
      return null;
    }
    if (value.characters.length > maxGraphemeClusters) {
      throw const DailyChoiceDescriptionValidationException(
        DailyChoiceDescriptionValidationFailure(
          field: DailyChoiceDescriptionField.description,
          reason: DailyChoiceDescriptionValidationReason.tooLong,
        ),
      );
    }
    return value;
  }

  @override
  bool operator ==(Object other) =>
      other is DailyChoiceDescription && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'DailyChoiceDescription';
}
