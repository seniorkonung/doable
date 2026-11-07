import 'package:uuid/uuid.dart';

sealed class ActionIdDecoding {
  const ActionIdDecoding();
}

final class ActionIdDecodingSuccess extends ActionIdDecoding {
  const ActionIdDecodingSuccess(this.id);

  final ActionId id;
}

final class InvalidActionIdDecoding extends ActionIdDecoding {
  const InvalidActionIdDecoding();
}

final class ActionId implements Comparable<ActionId> {
  const ActionId._(this._uuid);

  final UuidValue _uuid;

  static ActionIdDecoding decode(String serialized) {
    if (serialized != serialized.toLowerCase()) {
      return const InvalidActionIdDecoding();
    }

    try {
      final uuid = UuidValue.withValidation(serialized);
      if (uuid.isNil || uuid.uuid != serialized) {
        return const InvalidActionIdDecoding();
      }
      return ActionIdDecodingSuccess(ActionId._(uuid));
    } on FormatException {
      return const InvalidActionIdDecoding();
    }
  }

  String toCanonicalString() => _uuid.uuid;

  @override
  int compareTo(ActionId other) => _uuid.uuid.compareTo(other._uuid.uuid);

  @override
  bool operator ==(Object other) => other is ActionId && other._uuid == _uuid;

  @override
  int get hashCode => _uuid.hashCode;

  @override
  String toString() => 'ActionId';
}
