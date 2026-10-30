import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../app/navigation/graph_generation.dart';
import '../../../graph/application/graph_command_coordinator.dart';
import '../../../graph/application/graph_revision.dart';
import '../../../tag/application/tag_change.dart';
import '../../../tag/domain/tag_id.dart';
import '../../application/intention_catalog.dart';
import 'intention_catalog_purpose.dart';
import 'intention_catalog_view_model.dart';

part 'intention_tag_conditions_view_model.g.dart';

/// Узкая зависимость позволяет проверять снятие условий без команд.
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
  mustBeAbsent,
}

/// Выбранное условие: идентичность задаёт только [tagId].
final class IntentionTagCondition {
  const IntentionTagCondition({required this.tagId, required this.requirement});

  final TagId tagId;
  final IntentionTagRequirement requirement;

  @override
  bool operator ==(Object other) =>
      other is IntentionTagCondition &&
      other.tagId == tagId &&
      other.requirement == requirement;

  @override
  int get hashCode => Object.hash(tagId, requirement);
}

/// Условия одного назначения поиска, по одному на тег.
final class IntentionTagConditionsState {
  IntentionTagConditionsState(Iterable<IntentionTagCondition> conditions)
    : conditions = List.unmodifiable(conditions);

  final List<IntentionTagCondition> conditions;

  /// Предикат поиска по этим условиям.
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

  /// Переключает условие по тегу [tagId] по кругу: без условия — «должен
  /// быть», «должен быть» — «должен отсутствовать», «должен отсутствовать» —
  /// без условия.
  ///
  /// Тег, удаление которого уже подтверждено, ни условий, ни выдачи не меняет.
  void cycle(TagId tagId);

  /// Снимает все условия по тегам одним изменением фильтра поиска.
  void clear();
}

/// Выбранные условия по тегам одного назначения поиска.
///
/// Изменение условий сразу передаётся модели каталога того же назначения.
/// Модель не выполняет команд тегов и ничего не читает: снятие условия при
/// удалении тега следует за подтверждёнными пакетами изменений.
/// Условия живут, пока открыт их поиск, и между открытиями не сохраняются.
@riverpod
final class IntentionTagConditionsViewModel
    extends _$IntentionTagConditionsViewModel
    implements IntentionTagConditionSet {
  late IntentionCatalogPurpose _purpose;
  StreamSubscription<ConfirmedGraphChangePackage>? _changes;
  final _conditionChanges =
      StreamController<IntentionTagConditionsState>.broadcast();
  final _requirements = <TagId, IntentionTagRequirement>{};

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
      _requirements.clear();
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

  @override
  IntentionTagConditionsState get current => state;

  @override
  Stream<IntentionTagConditionsState> get changes => _conditionChanges.stream;

  @override
  void cycle(TagId tagId) {
    if (_deletedTagIds.contains(tagId)) return;
    switch (_requirements[tagId]) {
      case null:
        _requirements[tagId] = IntentionTagRequirement.mustBePresent;
      case IntentionTagRequirement.mustBePresent:
        _requirements[tagId] = IntentionTagRequirement.mustBeAbsent;
      case IntentionTagRequirement.mustBeAbsent:
        _requirements.remove(tagId);
    }
    _publish();
  }

  @override
  void clear() {
    if (_requirements.isEmpty) return;
    _requirements.clear();
    _publish();
  }

  void _onPackage(ConfirmedGraphChangePackage package) {
    if (!ref.mounted) return;
    var changed = false;
    for (final change in package.changes) {
      switch (change) {
        // Модель каталога сама исключает тег из применённого фильтра в
        // этой же публикации пакета, поэтому фильтр не публикуется повторно.
        case TagDeletedChange(:final tagId):
          _deletedTagIds.add(tagId);
          changed = _requirements.remove(tagId) != null || changed;
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
    for (final MapEntry(key: tagId, value: requirement)
        in _requirements.entries)
      IntentionTagCondition(tagId: tagId, requirement: requirement),
  ]);
}
