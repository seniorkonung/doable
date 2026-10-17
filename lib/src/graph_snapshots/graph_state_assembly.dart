import '../graph_format/graph_format_records.dart';
import '../intention/domain/intention.dart';

/// Базовое состояние сборки: пустой граф позиции 0 или записи состояния на
/// позиции, например снимка.
final class GraphStateBase {
  const GraphStateBase({required this.position, required this.readRecords});

  const GraphStateBase.empty() : position = 0, readRecords = _noRecords;

  final int position;

  /// Каждый вызов заново открывает записи состояния в каноническом порядке
  /// файла формата: сборка читает их дважды.
  final Stream<GraphEntityRecord> Function() readRecords;
}

Stream<GraphEntityRecord> _noRecords() => const Stream.empty();

/// Пакет фактов лога с его позицией; факты прочитаны в текущей версии
/// формата.
final class GraphFactPackage {
  const GraphFactPackage({required this.position, required this.facts});

  final int position;
  final List<GraphFact> facts;
}

/// Состояние графа, собранное на позиции.
final class AssembledGraphState {
  const AssembledGraphState._(this.counts, this.records);

  /// Количества записей известны до первой записи, поэтому из них пишется
  /// заголовок файла формата.
  final GraphRecordCounts counts;

  /// Записи в каноническом порядке файла формата, которые выдаются по мере
  /// чтения базового состояния. Поток однократный.
  final Stream<GraphEntityRecord> records;
}

/// Потоковая сборка состояния графа из базового состояния и пакетов фактов
/// после него.
abstract final class GraphStateAssembly {
  /// Собирает состояние на позиции последнего из пакетов [packages], а без
  /// них — на позиции [base].
  ///
  /// Пакеты должны идти по возрастанию позиций после позиции [base], иначе
  /// сборка отказывает [StateError]. В памяти держится только итог фактов
  /// пакетов по сущностям, а базовое состояние читается построчно: сначала
  /// ради количеств результата, затем при прослушивании
  /// [AssembledGraphState.records].
  ///
  /// Изменённые сущности базы остаются на своих местах, удалённые
  /// выбрасываются. Созданные встают в порядок, в каком сущности перечисляет
  /// база: намерения — по времени создания и идентификатору, остальные —
  /// после сущностей базы своей секции по месту последнего создания в
  /// пакетах. Сущность, удалённая и снова созданная с тем же ключом,
  /// покидает прежнее место, как строка базы с новой последовательностью
  /// создания.
  static Future<AssembledGraphState> assemble(
    GraphStateBase base,
    Stream<GraphFactPackage> packages,
  ) async {
    final outcomes = await _summarize(base.position, packages);

    final counts = List.filled(_Section.values.length, 0);
    await for (final record in base.readRecords()) {
      final outcome = outcomes[_keyOf(record)];
      if (outcome == null) {
        counts[_Section.of(record).index]++;
      } else {
        outcome.isInBase = true;
      }
    }
    final created = [for (final _ in _Section.values) <_Life>[]];
    for (final outcome in outcomes.values) {
      final life = outcome.life;
      if (life == null) continue;
      final section = _Section.of(life.record).index;
      counts[section]++;
      if (outcome.isCreated) created[section].add(life);
    }

    return AssembledGraphState._(
      GraphRecordCounts(
        tags: counts[_Section.tags.index],
        intentions: counts[_Section.intentions.index],
        tagAssignments: counts[_Section.tagAssignments.index],
        longTermRelations: counts[_Section.longTermRelations.index],
        dailyChoices: counts[_Section.dailyChoices.index],
      ),
      _assembledRecords(base, outcomes, _Creations(created)),
    );
  }
}

Future<Map<GraphEntityKey, _Outcome>> _summarize(
  int basePosition,
  Stream<GraphFactPackage> packages,
) async {
  final outcomes = <GraphEntityKey, _Outcome>{};
  var position = basePosition;
  var factNumber = 0;
  await for (final package in packages) {
    if (package.position <= position) {
      throw StateError(
        'Пакеты фактов идут не по возрастанию позиций после базового '
        'состояния.',
      );
    }
    position = package.position;
    for (final fact in package.facts) {
      switch (fact) {
        case GraphEntityRecord():
          outcomes
              .putIfAbsent(_keyOf(fact), _Outcome.new)
              .change(fact, factNumber);
        case GraphEntityDeletion(:final entity):
          outcomes.putIfAbsent(entity, _Outcome.new).delete();
      }
      factNumber++;
    }
  }
  return outcomes;
}

Stream<GraphEntityRecord> _assembledRecords(
  GraphStateBase base,
  Map<GraphEntityKey, _Outcome> outcomes,
  _Creations created,
) async* {
  await for (final record in base.readRecords()) {
    for (final creation in created.takeBefore(record)) {
      yield creation;
    }
    final outcome = outcomes[_keyOf(record)];
    if (outcome == null) {
      yield record;
    } else if (outcome.replacement case final replacement?) {
      yield replacement;
    }
  }
  for (final creation in created.takeRest()) {
    yield creation;
  }
}

/// Итог фактов пакетов об одной сущности.
final class _Outcome {
  /// Состояние после пакетов; `null` — сущность удалена.
  _Life? life;

  /// Сущность удалялась в пакетах, поэтому её последнее состояние создано в
  /// них заново.
  var wasDeleted = false;

  /// Сущность есть в базовом состоянии.
  var isInBase = false;

  /// Сущность встаёт на место созданной, а не на своё место в базе.
  bool get isCreated => life != null && (wasDeleted || !isInBase);

  /// Запись на месте сущности базы; `null` — место освобождается.
  GraphEntityRecord? get replacement => wasDeleted ? null : life?.record;

  void change(GraphEntityRecord record, int factNumber) =>
      life = (record: record, creation: life?.creation ?? factNumber);

  void delete() {
    life = null;
    wasDeleted = true;
  }
}

/// Последнее состояние сущности и номер факта её последнего создания.
/// Факты нумеруются подряд по пакетам, поэтому номер упорядочивает по
/// позиции пакета и месту факта в нём.
typedef _Life = ({GraphEntityRecord record, int creation});

/// Созданные в пакетах записи по секциям, которые выдаются вперемешку с
/// записями базового состояния.
final class _Creations {
  _Creations(List<List<_Life>> bySection)
    : _bySection = [
        for (final lives in bySection)
          [for (final life in lives..sort(_compareCreated)) life.record],
      ];

  final List<List<GraphEntityRecord>> _bySection;
  var _section = 0;
  var _next = 0;

  /// Созданные записи, которые идут перед записью базы [record]: оставшиеся
  /// записи предшествующих секций и записи её секции, которые встают перед
  /// ней.
  Iterable<GraphEntityRecord> takeBefore(GraphEntityRecord record) sync* {
    final section = _Section.of(record).index;
    while (_section < section) {
      yield* _takeSection();
    }
    final records = _bySection[_section];
    while (_next < records.length && _precedes(records[_next], record)) {
      yield records[_next++];
    }
  }

  Iterable<GraphEntityRecord> takeRest() sync* {
    while (_section < _bySection.length) {
      yield* _takeSection();
    }
  }

  Iterable<GraphEntityRecord> _takeSection() sync* {
    final records = _bySection[_section];
    while (_next < records.length) {
      yield records[_next++];
    }
    _section++;
    _next = 0;
  }
}

/// Порядок созданных записей одной секции.
int _compareCreated(_Life first, _Life second) =>
    switch ((first.record, second.record)) {
      (
        IntentionRecord(intention: final firstIntention),
        IntentionRecord(intention: final secondIntention),
      ) =>
        _compareIntentions(firstIntention, secondIntention),
      _ => first.creation.compareTo(second.creation),
    };

/// Встаёт ли созданная запись [created] перед записью базы [base] той же
/// секции. Остальные секции упорядочены последовательностью создания, и
/// созданные встают в них после записей базы.
bool _precedes(GraphEntityRecord created, GraphEntityRecord base) =>
    switch ((created, base)) {
      (
        IntentionRecord(intention: final createdIntention),
        IntentionRecord(intention: final baseIntention),
      ) =>
        _compareIntentions(createdIntention, baseIntention) < 0,
      _ => false,
    };

/// Порядок намерений в базе и в файле формата: по времени создания, затем по
/// идентификатору. Время создания — показание часов устройства, поэтому
/// созданное позже намерение может встать перед прежними.
int _compareIntentions(Intention first, Intention second) {
  final byCreation = first.createdAt.value.compareTo(second.createdAt.value);
  return byCreation != 0 ? byCreation : first.id.compareTo(second.id);
}

GraphEntityKey _keyOf(GraphEntityRecord record) => switch (record) {
  TagRecord(:final tag) => TagKey(tag.id),
  IntentionRecord(:final intention) => IntentionKey(intention.id),
  TagAssignmentRecord(:final assignment) => TagAssignmentKey(assignment),
  LongTermRelationRecord(:final id) => LongTermRelationKey(id),
  DailyChoiceRecord(:final choice) => DailyChoiceKey(choice.id),
};

/// Секции в порядке файла формата.
enum _Section {
  tags,
  intentions,
  tagAssignments,
  longTermRelations,
  dailyChoices;

  static _Section of(GraphEntityRecord record) => switch (record) {
    TagRecord() => tags,
    IntentionRecord() => intentions,
    TagAssignmentRecord() => tagAssignments,
    LongTermRelationRecord() => longTermRelations,
    DailyChoiceRecord() => dailyChoices,
  };
}
