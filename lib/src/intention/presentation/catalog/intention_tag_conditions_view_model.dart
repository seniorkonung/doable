import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../app/navigation/graph_generation.dart';
import '../../../graph/application/graph_command_coordinator.dart';
import '../../../graph/application/graph_revision.dart';
import '../../../tag/application/tag_change.dart';
import '../../../tag/domain/tag.dart';
import '../../../tag/domain/tag_color.dart';
import '../../../tag/domain/tag_id.dart';
import '../../../tag/domain/tag_name.dart';
import '../../application/intention_catalog.dart';
import 'intention_catalog_purpose.dart';
import 'intention_catalog_view_model.dart';

part 'intention_tag_conditions_view_model.g.dart';

/// Узкая зависимость позволяет проверять предъявление условий без команд.
final intentionTagConditionsChangesProvider =
    Provider<Stream<ConfirmedGraphChangePackage>>(
      (ref) => ref
          .watch(graphCommandCoordinatorProvider.notifier)
          .completions
          .map((completion) => completion.confirmedChange)
          .where((package) => package != null)
          .cast<ConfirmedGraphChangePackage>(),
    );

/// Надобность условия поиска по тегу.
enum IntentionTagRequirement {
  /// Тег должен быть назначен искомому намерению.
  mustBePresent,

  /// Тег должен отсутствовать у искомого намерения.
  mustBeAbsent;

  IntentionTagRequirement get toggled => switch (this) {
    mustBePresent => mustBeAbsent,
    mustBeAbsent => mustBePresent,
  };
}

/// Выбранное условие для предъявления: идентичность задаёт только [tagId].
///
/// Название и цвет в предикат поиска не входят.
final class IntentionTagCondition {
  const IntentionTagCondition({
    required this.tagId,
    required this.requirement,
    required this.name,
    required this.color,
  });

  final TagId tagId;
  final IntentionTagRequirement requirement;
  final TagName name;

  /// `null` — «Без цвета».
  final TagColor? color;

  @override
  bool operator ==(Object other) =>
      other is IntentionTagCondition &&
      other.tagId == tagId &&
      other.requirement == requirement &&
      other.name == name &&
      other.color == color;

  @override
  int get hashCode => Object.hash(tagId, requirement, name, color);
}

/// Выбор тега с надобностью из снимка каталога тегов на [snapshotRevision].
final class IntentionTagConditionSelection {
  const IntentionTagConditionSelection({
    required this.tag,
    required this.requirement,
    required this.snapshotRevision,
  });

  final Tag tag;
  final IntentionTagRequirement requirement;
  final GraphRevision snapshotRevision;
}

/// Условия одного назначения поиска в порядке добавления, по одному на тег.
final class IntentionTagConditionsState {
  IntentionTagConditionsState(Iterable<IntentionTagCondition> conditions)
    : conditions = List.unmodifiable(conditions);

  final List<IntentionTagCondition> conditions;

  /// Предикат поиска: порядок добавления и предъявление в него не входят.
  IntentionTagFilter get tagFilter => IntentionTagFilter(
    requiredTagIds: _tagIds(IntentionTagRequirement.mustBePresent),
    excludedTagIds: _tagIds(IntentionTagRequirement.mustBeAbsent),
  );

  Iterable<TagId> _tagIds(IntentionTagRequirement requirement) => [
    for (final condition in conditions)
      if (condition.requirement == requirement) condition.tagId,
  ];
}

/// Узкий контракт условий по тегам одного поиска для панели тегов.
///
/// Предоставляет только наблюдаемые условия и их явные изменения: условия
/// живут в сессии поиска, поэтому команды тегов, чтения графа и детали
/// хранилища в контракт не входят.
abstract interface class IntentionTagConditionSet {
  IntentionTagConditionsState get current;

  /// Изменения условий, в том числе снятие условия при удалении тега.
  Stream<IntentionTagConditionsState> get changes;

  /// Переключает условие по [tag] по кругу: без условия — «должен быть» в
  /// конце порядка, «должен быть» — «должен отсутствовать» на прежнем месте,
  /// «должен отсутствовать» — без условия.
  ///
  /// Название и цвет берутся из [tag] снимка на [snapshotRevision], если он
  /// не старше уже подтверждённого предъявления условия. Тег, удаление
  /// которого уже подтверждено, ни условий, ни выдачи не меняет.
  void cycle(Tag tag, {required GraphRevision snapshotRevision});

  /// Снимает все условия по тегам одним изменением фильтра поиска.
  void clear();
}

/// Выбранные условия по тегам одного назначения поиска.
///
/// Изменение условий сразу передаётся модели каталога того же назначения.
/// Модель не выполняет команд тегов и ничего не читает: предъявление
/// условий следует за подтверждёнными пакетами изменений.
/// Условия живут, пока открыт их поиск, и между открытиями не сохраняются.
@riverpod
final class IntentionTagConditionsViewModel
    extends _$IntentionTagConditionsViewModel
    implements IntentionTagConditionSet {
  late IntentionCatalogPurpose _purpose;
  StreamSubscription<ConfirmedGraphChangePackage>? _changes;
  final _conditionChanges =
      StreamController<IntentionTagConditionsState>.broadcast();
  final _entries = <TagId, _ConditionEntry>{};

  /// Теги, удаление которых подтверждено в текущем поколении графа.
  final _deletedTagIds = <TagId>{};

  /// Поколение графа, для которого выбраны условия.
  GraphGeneration? _graphGeneration;

  @override
  IntentionTagConditionsState build(IntentionCatalogPurpose purpose) {
    // Новое поколение графа начинает поиск без условий, а другое
    // перестроение их сохраняет.
    final graphGeneration = ref.watch(currentGraphGenerationProvider);
    if (graphGeneration != _graphGeneration) {
      _graphGeneration = graphGeneration;
      _entries.clear();
      _deletedTagIds.clear();
    }
    unawaited(_changes?.cancel());
    _purpose = purpose;
    _changes = ref
        .watch(intentionTagConditionsChangesProvider)
        .listen(_onPackage);
    ref.onDispose(() => unawaited(_changes?.cancel()));
    listenSelf((_, next) => _conditionChanges.add(next));
    // Модель каталога хранит применённый фильтр и живёт не меньше условий.
    ref.listen(intentionCatalogViewModelProvider(purpose), (_, _) {});
    return _snapshot();
  }

  /// Добавляет условие по выбранному тегу либо меняет надобность уже
  /// существующего условия, сохраняя его место.
  ///
  /// Выбор тега из снимка, устаревшего к подтверждённому удалению этого тега,
  /// не меняет ни условий, ни выдачи.
  void applySelection(IntentionTagConditionSelection selection) {
    final IntentionTagConditionSelection(
      :tag,
      :requirement,
      :snapshotRevision,
    ) = selection;
    if (_deletedTagIds.contains(tag.id)) return;
    _put(tag, requirement, snapshotRevision);
    _publish();
  }

  @override
  IntentionTagConditionsState get current => state;

  @override
  Stream<IntentionTagConditionsState> get changes => _conditionChanges.stream;

  @override
  void cycle(Tag tag, {required GraphRevision snapshotRevision}) {
    if (_deletedTagIds.contains(tag.id)) return;
    switch (_entries[tag.id]?.requirement) {
      case null:
        _put(tag, IntentionTagRequirement.mustBePresent, snapshotRevision);
      case IntentionTagRequirement.mustBePresent:
        _put(tag, IntentionTagRequirement.mustBeAbsent, snapshotRevision);
      case IntentionTagRequirement.mustBeAbsent:
        _entries.remove(tag.id);
    }
    _publish();
  }

  @override
  void clear() {
    if (_entries.isEmpty) return;
    _entries.clear();
    _publish();
  }

  /// Добавляет условие в конец порядка либо меняет надобность существующего
  /// на прежнем месте.
  void _put(
    Tag tag,
    IntentionTagRequirement requirement,
    GraphRevision snapshotRevision,
  ) {
    final existing = _entries[tag.id];
    if (existing == null) {
      _entries[tag.id] = _ConditionEntry(
        requirement: requirement,
        name: tag.name,
        color: tag.color,
        revision: snapshotRevision,
      );
      return;
    }
    existing.requirement = requirement;
    // Более ранний снимок не возвращает уже подтверждённое предъявление.
    if (snapshotRevision.compareTo(existing.revision) ==
        GraphRevisionOrder.newer) {
      existing
        ..name = tag.name
        ..color = tag.color
        ..revision = snapshotRevision;
    }
  }

  /// Переключает «должен быть ↔ должен отсутствовать» на прежнем месте.
  void toggleRequirement(TagId tagId) {
    final entry = _entries[tagId];
    if (entry == null) return;
    entry.requirement = entry.requirement.toggled;
    _publish();
  }

  /// Снимает условие.
  void remove(TagId tagId) {
    if (_entries.remove(tagId) == null) return;
    _publish();
  }

  void _onPackage(ConfirmedGraphChangePackage package) {
    if (!ref.mounted) return;
    var changed = false;
    for (final change in package.changes) {
      switch (change) {
        case TagUpdatedChange(:final after):
          final entry = _entries[after.id];
          if (entry == null || !_supersedes(package.revision, entry.revision)) {
            continue;
          }
          entry
            ..name = after.name
            ..color = after.color
            ..revision = package.revision;
          changed = true;
        // Модель каталога сама исключает тег из применённого фильтра в
        // этой же публикации пакета, поэтому фильтр не публикуется повторно.
        case TagDeletedChange(:final tagId):
          _deletedTagIds.add(tagId);
          changed = _entries.remove(tagId) != null || changed;
        // Новый тег с прежним названием имеет другой идентификатор и
        // снятое условие не восстанавливает.
        case GraphChange():
          break;
      }
    }
    if (changed) state = _snapshot();
  }

  void _publish() {
    final next = _snapshot();
    state = next;
    ref
        .read(intentionCatalogViewModelProvider(_purpose).notifier)
        .changeTagFilter(next.tagFilter);
  }

  IntentionTagConditionsState _snapshot() => IntentionTagConditionsState([
    for (final MapEntry(key: tagId, value: entry) in _entries.entries)
      IntentionTagCondition(
        tagId: tagId,
        requirement: entry.requirement,
        name: entry.name,
        color: entry.color,
      ),
  ]);

  bool _supersedes(GraphRevision revision, GraphRevision confirmed) =>
      switch (revision.compareTo(confirmed)) {
        GraphRevisionOrder.newer || GraphRevisionOrder.differentEpoch => true,
        GraphRevisionOrder.older || GraphRevisionOrder.same => false,
      };
}

/// Изменяемая запись условия; ключ [TagId] хранит порядок добавления.
final class _ConditionEntry {
  _ConditionEntry({
    required this.requirement,
    required this.name,
    required this.color,
    required this.revision,
  });

  IntentionTagRequirement requirement;
  TagName name;
  TagColor? color;

  /// Ревизия, на которой подтверждены предъявляемые название и цвет.
  GraphRevision revision;
}
