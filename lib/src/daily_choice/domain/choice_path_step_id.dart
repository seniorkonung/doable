import 'package:uuid/uuid.dart';

sealed class ChoicePathStepIdDecoding {
  const ChoicePathStepIdDecoding();
}

final class ChoicePathStepIdDecodingSuccess extends ChoicePathStepIdDecoding {
  const ChoicePathStepIdDecodingSuccess(this.id);

  final ChoicePathStepId id;
}

final class InvalidChoicePathStepIdDecoding extends ChoicePathStepIdDecoding {
  const InvalidChoicePathStepIdDecoding();
}

final class ChoicePathStepId implements Comparable<ChoicePathStepId> {
  const ChoicePathStepId._(this._uuid);

  final UuidValue _uuid;

  static ChoicePathStepIdDecoding decode(String serialized) {
    if (serialized != serialized.toLowerCase()) {
      return const InvalidChoicePathStepIdDecoding();
    }

    try {
      final uuid = UuidValue.withValidation(serialized);
      if (uuid.isNil || uuid.uuid != serialized) {
        return const InvalidChoicePathStepIdDecoding();
      }
      return ChoicePathStepIdDecodingSuccess(ChoicePathStepId._(uuid));
    } on FormatException {
      return const InvalidChoicePathStepIdDecoding();
    }
  }

  String toCanonicalString() => _uuid.uuid;

  @override
  int compareTo(ChoicePathStepId other) =>
      _uuid.uuid.compareTo(other._uuid.uuid);

  @override
  bool operator ==(Object other) =>
      other is ChoicePathStepId && other._uuid == _uuid;

  @override
  int get hashCode => _uuid.hashCode;

  @override
  String toString() => 'ChoicePathStepId';
}
