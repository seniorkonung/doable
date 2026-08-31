import 'package:uuid/uuid.dart';

import '../domain/intention_id.dart';

abstract interface class IntentionIdGenerator {
  IntentionId generate();
}

final class UuidV7IntentionIdGenerator implements IntentionIdGenerator {
  final Uuid _uuid = Uuid();

  @override
  IntentionId generate() => switch (IntentionId.decode(_uuid.v7obj().uuid)) {
    IntentionIdDecodingSuccess(:final id) => id,
    InvalidIntentionIdDecoding() => throw StateError(
      'Генератор UUID v7 вернул недопустимое значение.',
    ),
  };
}
