import 'package:uuid/uuid.dart';

import '../domain/long_term_relation_id.dart';

abstract interface class LongTermRelationIdGenerator {
  LongTermRelationId generate();
}

final class UuidV7LongTermRelationIdGenerator
    implements LongTermRelationIdGenerator {
  final Uuid _uuid = Uuid();

  @override
  LongTermRelationId generate() =>
      switch (LongTermRelationId.decode(_uuid.v7obj().uuid)) {
        LongTermRelationIdDecodingSuccess(:final id) => id,
        InvalidLongTermRelationIdDecoding() => throw StateError(
          'Генератор UUID v7 вернул недопустимое значение.',
        ),
      };
}
