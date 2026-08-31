import 'package:uuid/uuid.dart';

sealed class IntentionIdDecoding {
  const IntentionIdDecoding();
}

final class IntentionIdDecodingSuccess extends IntentionIdDecoding {
  const IntentionIdDecodingSuccess(this.id);

  final IntentionId id;
}

final class InvalidIntentionIdDecoding extends IntentionIdDecoding {
  const InvalidIntentionIdDecoding();
}

final class IntentionId implements Comparable<IntentionId> {
  const IntentionId._(this._uuid);

  final UuidValue _uuid;

  static IntentionIdDecoding decode(String serialized) {
    if (serialized != serialized.toLowerCase()) {
      return const InvalidIntentionIdDecoding();
    }

    try {
      final uuid = UuidValue.withValidation(serialized);
      if (uuid.isNil || uuid.uuid != serialized) {
        return const InvalidIntentionIdDecoding();
      }
      return IntentionIdDecodingSuccess(IntentionId._(uuid));
    } on FormatException {
      return const InvalidIntentionIdDecoding();
    }
  }

  String toCanonicalString() => _uuid.uuid;

  @override
  int compareTo(IntentionId other) => _uuid.uuid.compareTo(other._uuid.uuid);

  @override
  bool operator ==(Object other) =>
      other is IntentionId && other._uuid == _uuid;

  @override
  int get hashCode => _uuid.hashCode;

  @override
  String toString() => 'IntentionId';
}
