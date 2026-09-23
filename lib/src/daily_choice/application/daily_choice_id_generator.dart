import 'package:uuid/uuid.dart';

import '../domain/choice_path_step_id.dart';
import '../domain/daily_choice_id.dart';

abstract interface class DailyChoiceIdGenerator {
  DailyChoiceId generate();
}

abstract interface class ChoicePathStepIdGenerator {
  ChoicePathStepId generate();
}

final class UuidV7DailyChoiceIdGenerator implements DailyChoiceIdGenerator {
  final Uuid _uuid = Uuid();

  @override
  DailyChoiceId generate() =>
      switch (DailyChoiceId.decode(_uuid.v7obj().uuid)) {
        DailyChoiceIdDecodingSuccess(:final id) => id,
        InvalidDailyChoiceIdDecoding() => throw StateError(
          'Генератор UUID v7 вернул недопустимое значение.',
        ),
      };
}

final class UuidV7ChoicePathStepIdGenerator
    implements ChoicePathStepIdGenerator {
  final Uuid _uuid = Uuid();

  @override
  ChoicePathStepId generate() =>
      switch (ChoicePathStepId.decode(_uuid.v7obj().uuid)) {
        ChoicePathStepIdDecodingSuccess(:final id) => id,
        InvalidChoicePathStepIdDecoding() => throw StateError(
          'Генератор UUID v7 вернул недопустимое значение.',
        ),
      };
}
