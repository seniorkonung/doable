import 'package:uuid/uuid.dart';

sealed class LongTermRelationIdDecoding {
  const LongTermRelationIdDecoding();
}

final class LongTermRelationIdDecodingSuccess
    extends LongTermRelationIdDecoding {
  const LongTermRelationIdDecodingSuccess(this.id);

  final LongTermRelationId id;
}

final class InvalidLongTermRelationIdDecoding
    extends LongTermRelationIdDecoding {
  const InvalidLongTermRelationIdDecoding();
}

final class LongTermRelationId implements Comparable<LongTermRelationId> {
  const LongTermRelationId._(this._uuid);

  final UuidValue _uuid;

  static LongTermRelationIdDecoding decode(String serialized) {
    if (serialized != serialized.toLowerCase()) {
      return const InvalidLongTermRelationIdDecoding();
    }

    try {
      final uuid = UuidValue.withValidation(serialized);
      if (uuid.isNil || uuid.uuid != serialized) {
        return const InvalidLongTermRelationIdDecoding();
      }
      return LongTermRelationIdDecodingSuccess(LongTermRelationId._(uuid));
    } on FormatException {
      return const InvalidLongTermRelationIdDecoding();
    }
  }

  String toCanonicalString() => _uuid.uuid;

  @override
  int compareTo(LongTermRelationId other) =>
      _uuid.uuid.compareTo(other._uuid.uuid);

  @override
  bool operator ==(Object other) =>
      other is LongTermRelationId && other._uuid == _uuid;

  @override
  int get hashCode => _uuid.hashCode;

  @override
  String toString() => 'LongTermRelationId';
}
