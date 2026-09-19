import 'package:characters/characters.dart';

import '../../shared/domain/unicode_text.dart';

enum LongTermRelationTextField { description }

enum LongTermRelationTextValidationReason { tooLong, invalidUnicodeRepertoire }

final class LongTermRelationTextValidationFailure {
  const LongTermRelationTextValidationFailure({
    required this.field,
    required this.reason,
  });

  final LongTermRelationTextField field;
  final LongTermRelationTextValidationReason reason;
}

final class LongTermRelationTextValidationException implements Exception {
  const LongTermRelationTextValidationException(this.failure);

  final LongTermRelationTextValidationFailure failure;
}

final class LongTermRelationDescription {
  const LongTermRelationDescription._(this.value);

  static const int maxGraphemeClusters = 4096;

  static LongTermRelationDescription? fromInput(String value) {
    try {
      UnicodeText.ensureValidScalarValuesWithoutNul(value);
    } on InvalidUnicodeTextException {
      throw const LongTermRelationTextValidationException(
        LongTermRelationTextValidationFailure(
          field: LongTermRelationTextField.description,
          reason: LongTermRelationTextValidationReason.invalidUnicodeRepertoire,
        ),
      );
    }

    if (value.trim().isEmpty) {
      return null;
    }
    if (value.characters.length > maxGraphemeClusters) {
      throw const LongTermRelationTextValidationException(
        LongTermRelationTextValidationFailure(
          field: LongTermRelationTextField.description,
          reason: LongTermRelationTextValidationReason.tooLong,
        ),
      );
    }
    return LongTermRelationDescription._(value);
  }

  final String value;

  @override
  bool operator ==(Object other) =>
      other is LongTermRelationDescription && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'LongTermRelationDescription';
}
