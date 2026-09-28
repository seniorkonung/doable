import 'package:uuid/uuid.dart';

sealed class TagIdDecoding {
  const TagIdDecoding();
}

final class TagIdDecodingSuccess extends TagIdDecoding {
  const TagIdDecodingSuccess(this.id);

  final TagId id;
}

final class InvalidTagIdDecoding extends TagIdDecoding {
  const InvalidTagIdDecoding();
}

final class TagId implements Comparable<TagId> {
  const TagId._(this._uuid);

  final UuidValue _uuid;

  static TagIdDecoding decode(String serialized) {
    if (serialized != serialized.toLowerCase()) {
      return const InvalidTagIdDecoding();
    }

    try {
      final uuid = UuidValue.withValidation(serialized);
      if (uuid.isNil || uuid.uuid != serialized) {
        return const InvalidTagIdDecoding();
      }
      return TagIdDecodingSuccess(TagId._(uuid));
    } on FormatException {
      return const InvalidTagIdDecoding();
    }
  }

  String toCanonicalString() => _uuid.uuid;

  @override
  int compareTo(TagId other) => _uuid.uuid.compareTo(other._uuid.uuid);

  @override
  bool operator ==(Object other) => other is TagId && other._uuid == _uuid;

  @override
  int get hashCode => _uuid.hashCode;

  @override
  String toString() => 'TagId';
}
