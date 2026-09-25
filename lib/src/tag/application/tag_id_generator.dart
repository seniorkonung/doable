import 'package:uuid/uuid.dart';

import '../domain/tag_id.dart';

abstract interface class TagIdGenerator {
  TagId generate();
}

final class UuidV7TagIdGenerator implements TagIdGenerator {
  final Uuid _uuid = Uuid();

  @override
  TagId generate() => switch (TagId.decode(_uuid.v7obj().uuid)) {
    TagIdDecodingSuccess(:final id) => id,
    InvalidTagIdDecoding() => throw StateError(
      'Генератор UUID v7 вернул недопустимое значение.',
    ),
  };
}
