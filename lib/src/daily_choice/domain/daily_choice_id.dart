import 'package:uuid/uuid.dart';

sealed class DailyChoiceIdDecoding {
  const DailyChoiceIdDecoding();
}

final class DailyChoiceIdDecodingSuccess extends DailyChoiceIdDecoding {
  const DailyChoiceIdDecodingSuccess(this.id);

  final DailyChoiceId id;
}

final class InvalidDailyChoiceIdDecoding extends DailyChoiceIdDecoding {
  const InvalidDailyChoiceIdDecoding();
}

final class DailyChoiceId implements Comparable<DailyChoiceId> {
  const DailyChoiceId._(this._uuid);

  final UuidValue _uuid;

  static DailyChoiceIdDecoding decode(String serialized) {
    if (serialized != serialized.toLowerCase()) {
      return const InvalidDailyChoiceIdDecoding();
    }

    try {
      final uuid = UuidValue.withValidation(serialized);
      if (uuid.isNil || uuid.uuid != serialized) {
        return const InvalidDailyChoiceIdDecoding();
      }
      return DailyChoiceIdDecodingSuccess(DailyChoiceId._(uuid));
    } on FormatException {
      return const InvalidDailyChoiceIdDecoding();
    }
  }

  String toCanonicalString() => _uuid.uuid;

  @override
  int compareTo(DailyChoiceId other) => _uuid.uuid.compareTo(other._uuid.uuid);

  @override
  bool operator ==(Object other) =>
      other is DailyChoiceId && other._uuid == _uuid;

  @override
  int get hashCode => _uuid.hashCode;

  @override
  String toString() => 'DailyChoiceId';
}
