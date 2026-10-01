import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../graph/application/graph_command_coordinator.dart';
import '../../../graph/application/graph_command_result.dart';
import '../../../graph/application/graph_revision.dart';
import '../../../graph/application/personal_graph_repository_provider.dart';
import '../../../tag/application/tag_change.dart';
import '../../../tag/application/tag_read_result.dart';
import '../../../tag/domain/tag.dart';
import '../../../tag/domain/tag_id.dart';
import '../../../tag/domain/tag_name.dart';
import '../../application/intention_catalog.dart';
import 'intention_catalog_purpose.dart';
import 'intention_catalog_view_model.dart';

part 'intention_tag_conditions_view_model.g.dart';

/// Узкие зависимости позволяют проверять предъявление условий без команд.
final intentionTagConditionsReaderProvider = Provider<TagReadContract>(
  (ref) => ref.watch(personalGraphRepositoryProvider),
);

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
/// [name] — актуальное название либо последнее известное, если удаление тега
/// подтверждено. Название и признак удаления в предикат поиска не входят.
final class IntentionTagCondition {
  const IntentionTagCondition({
    required this.tagId,
    required this.requirement,
    required this.name,
    required this.isDeleted,
  });

  final TagId tagId;
  final IntentionTagRequirement requirement;
  final TagName name;
  final bool isDeleted;

  @override
  bool operator ==(Object other) =>
      other is IntentionTagCondition &&
      other.tagId == tagId &&
      other.requirement == requirement &&
      other.name == name &&
      other.isDeleted == isDeleted;

  @override
  int get hashCode => Object.hash(tagId, requirement, name, isDeleted);
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

/// Выбранные условия по тегам одного назначения поиска.
///
/// Изменение условий сразу передаётся модели каталога того же назначения.
/// Модель не выполняет команд тегов и не читает выдачу: читается только
/// текущее состояние тега, выбранного из возможно устаревшего снимка.
/// Условия живут, пока открыт их поиск, и между открытиями не сохраняются.
@riverpod
final class IntentionTagConditionsViewModel
    extends _$IntentionTagConditionsViewModel {
  late IntentionCatalogPurpose _purpose;
  late TagReadContract _reads;
  StreamSubscription<ConfirmedGraphChangePackage>? _changes;
  final _entries = <TagId, _ConditionEntry>{};

  /// Новейшая ревизия графа, о подтверждении которой знает модель.
  GraphRevision? _knownRevision;

  @override
  IntentionTagConditionsState build(IntentionCatalogPurpose purpose) {
    unawaited(_changes?.cancel());
    _purpose = purpose;
    _reads = ref.watch(intentionTagConditionsReaderProvider);
    _changes = ref
        .watch(intentionTagConditionsChangesProvider)
        .listen(_onPackage);
    ref.onDispose(() => unawaited(_changes?.cancel()));
    // Модель каталога хранит применённый фильтр и живёт не меньше условий.
    ref.listen(intentionCatalogViewModelProvider(purpose), (_, _) {});
    return _snapshot();
  }

  /// Добавляет условие по выбранному тегу либо меняет надобность уже
  /// существующего условия, сохраняя его место.
  void applySelection(IntentionTagConditionSelection selection) {
    final IntentionTagConditionSelection(
      :tag,
      :requirement,
      :snapshotRevision,
    ) = selection;
    final isCurrent = _isCurrent(snapshotRevision);
    _noteRevision(snapshotRevision);
    final existing = _entries[tag.id];
    if (existing == null) {
      _entries[tag.id] = _ConditionEntry(
        requirement: requirement,
        name: tag.name,
        revision: snapshotRevision,
        needsVerification: !isCurrent,
      );
    } else {
      existing.requirement = requirement;
      // Более ранний снимок не возвращает уже подтверждённое предъявление.
      if (!existing.isDeleted &&
          snapshotRevision.compareTo(existing.revision) ==
              GraphRevisionOrder.newer) {
        existing
          ..name = tag.name
          ..revision = snapshotRevision
          ..needsVerification = !isCurrent;
      }
    }
    _publish();
    _verifyPending();
  }

  /// Переключает «должен быть ↔ должен отсутствовать» на прежнем месте.
  void toggleRequirement(TagId tagId) {
    final entry = _entries[tagId];
    if (entry == null) return;
    entry.requirement = entry.requirement.toggled;
    _publish();
  }

  /// Снимает условие, в том числе по удалённому тегу.
  void remove(TagId tagId) {
    if (_entries.remove(tagId) == null) return;
    _publish();
  }

  void _onPackage(ConfirmedGraphChangePackage package) {
    if (!ref.mounted) return;
    _noteRevision(package.revision);
    var changed = false;
    for (final change in package.changes) {
      switch (change) {
        case TagRenamedChange(:final after):
          final entry = _entries[after.id];
          if (entry == null ||
              entry.isDeleted ||
              !_supersedes(package.revision, entry.revision)) {
            continue;
          }
          entry
            ..name = after.name
            ..revision = package.revision
            ..needsVerification = false;
          changed = true;
        case TagDeletedChange(:final tagId):
          final entry = _entries[tagId];
          if (entry == null ||
              entry.isDeleted ||
              !_supersedes(package.revision, entry.revision)) {
            continue;
          }
          entry
            ..isDeleted = true
            ..revision = package.revision
            ..needsVerification = false;
          changed = true;
        // Новый тег с прежним названием имеет другой идентификатор и
        // условие не затрагивает: признак удаления не снимается.
        case GraphChange():
          break;
      }
    }
    if (changed) state = _snapshot();
    // Неудавшееся уточнение повторяется событием пакета, без таймеров.
    _verifyPending();
  }

  void _verifyPending() {
    for (final MapEntry(key: tagId, value: entry) in _entries.entries) {
      if (entry.needsVerification && !entry.isVerifying) {
        unawaited(_verify(tagId, entry));
      }
    }
  }

  /// Уточняет предъявление условия, выбранного из снимка, после которого
  /// тег мог быть переименован или удалён.
  Future<void> _verify(TagId tagId, _ConditionEntry entry) async {
    entry.isVerifying = true;
    final result = await _readTag(tagId);
    entry.isVerifying = false;
    if (!ref.mounted ||
        !identical(_entries[tagId], entry) ||
        !entry.needsVerification) {
      return;
    }
    // Отказ чтения не подтверждает удаление: условие остаётся прежним.
    if (result case GraphResultSuccess(:final value)) {
      _noteRevision(value.revision);
      final tag = value.value;
      if (value.revision.compareTo(entry.revision) ==
              GraphRevisionOrder.older ||
          (tag != null && tag.id != tagId)) {
        return;
      }
      entry
        ..revision = value.revision
        ..needsVerification = false;
      if (tag == null) {
        entry.isDeleted = true;
      } else {
        entry.name = tag.name;
      }
      state = _snapshot();
    }
  }

  Future<TagReadResult> _readTag(TagId tagId) async {
    try {
      return await _reads.watchTag(tagId).first;
    } on Object {
      return const TagReadError(TagReadUnexpectedFailure());
    }
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
        isDeleted: entry.isDeleted,
      ),
  ]);

  /// Снимок не старше известной ревизии уже отражает все подтверждённые
  /// изменения; более новые пакеты модель получит сама.
  bool _isCurrent(GraphRevision snapshotRevision) {
    final known = _knownRevision;
    if (known == null) return false;
    return switch (snapshotRevision.compareTo(known)) {
      GraphRevisionOrder.same || GraphRevisionOrder.newer => true,
      GraphRevisionOrder.older || GraphRevisionOrder.differentEpoch => false,
    };
  }

  void _noteRevision(GraphRevision revision) {
    final known = _knownRevision;
    if (known == null || _supersedes(revision, known)) {
      _knownRevision = revision;
    }
  }

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
    required this.revision,
    required this.needsVerification,
  });

  IntentionTagRequirement requirement;
  TagName name;
  bool isDeleted = false;

  /// Ревизия, на которой подтверждено предъявляемое название или удаление.
  GraphRevision revision;

  /// Предъявление взято из снимка, который мог устареть к моменту выбора.
  bool needsVerification;
  bool isVerifying = false;
}
