import '../../graph/application/graph_revision.dart';
import '../../shared/domain/text_preview.dart';
import '../../tag/domain/tag.dart';
import '../../tag/domain/tag_id.dart';
import '../domain/intention.dart';
import '../domain/intention_id.dart';
import '../domain/intention_text.dart';
import 'title_search_key.dart';

enum IntentionScope { active, archived, all }

enum IntentionReadinessFilter { all, readyOnly, notReadyOnly }

/// Какие числа несёт первая порция каталога кроме общего количества.
enum IntentionCatalogCounting {
  /// Только общее количество.
  totalOnly,

  /// Числа типов в охвате запроса.
  byType,

  /// Числа типов отдельно в активном и архивном охватах.
  byScopeAndType,
}

/// Неизменяемые условия наличия и отсутствия собственных тегов намерения.
///
/// Повторы и порядок идентификаторов не меняют равенство условий.
/// Пересечение наборов сохраняется и делает сочетание невыполнимым.
/// Переименование и удаление тега сохраняют его идентификатор в условиях.
final class IntentionTagFilter {
  IntentionTagFilter({
    Iterable<TagId> requiredTagIds = const [],
    Iterable<TagId> excludedTagIds = const [],
  }) : requiredTagIds = Set.unmodifiable(requiredTagIds),
       excludedTagIds = Set.unmodifiable(excludedTagIds);

  const IntentionTagFilter._({
    required this.requiredTagIds,
    required this.excludedTagIds,
  });

  static const empty = IntentionTagFilter._(
    requiredTagIds: {},
    excludedTagIds: {},
  );

  final Set<TagId> requiredTagIds;
  final Set<TagId> excludedTagIds;

  /// Проверяет полный набор собственных назначений искомому намерению.
  bool matches(Set<TagId> ownTagIds) =>
      ownTagIds.containsAll(requiredTagIds) &&
      !excludedTagIds.any(ownTagIds.contains);

  @override
  bool operator ==(Object other) =>
      other is IntentionTagFilter &&
      requiredTagIds.length == other.requiredTagIds.length &&
      excludedTagIds.length == other.excludedTagIds.length &&
      requiredTagIds.containsAll(other.requiredTagIds) &&
      excludedTagIds.containsAll(other.excludedTagIds);

  @override
  int get hashCode => Object.hash(
    Object.hashAllUnordered(requiredTagIds),
    Object.hashAllUnordered(excludedTagIds),
  );
}

enum IntentionCatalogSortField { createdAt, updatedAt, title }

enum IntentionCatalogSortDirection { ascending, descending }

final class IntentionCatalogOrder {
  const IntentionCatalogOrder({required this.field, required this.direction});

  static const createdAtAscending = IntentionCatalogOrder(
    field: IntentionCatalogSortField.createdAt,
    direction: IntentionCatalogSortDirection.ascending,
  );

  static const createdAtDescending = IntentionCatalogOrder(
    field: IntentionCatalogSortField.createdAt,
    direction: IntentionCatalogSortDirection.descending,
  );

  static const updatedAtAscending = IntentionCatalogOrder(
    field: IntentionCatalogSortField.updatedAt,
    direction: IntentionCatalogSortDirection.ascending,
  );

  static const updatedAtDescending = IntentionCatalogOrder(
    field: IntentionCatalogSortField.updatedAt,
    direction: IntentionCatalogSortDirection.descending,
  );

  static const titleAscending = IntentionCatalogOrder(
    field: IntentionCatalogSortField.title,
    direction: IntentionCatalogSortDirection.ascending,
  );

  static const titleDescending = IntentionCatalogOrder(
    field: IntentionCatalogSortField.title,
    direction: IntentionCatalogSortDirection.descending,
  );

  final IntentionCatalogSortField field;
  final IntentionCatalogSortDirection direction;

  @override
  bool operator ==(Object other) =>
      other is IntentionCatalogOrder &&
      other.field == field &&
      other.direction == direction;

  @override
  int get hashCode => Object.hash(field, direction);
}

enum IntentionCatalogQueryValidationFailure {
  pageSizeOutOfRange,
  titleFilterTooLong,
  invalidUnicodeRepertoire,
}

final class IntentionCatalogQueryValidationException implements Exception {
  const IntentionCatalogQueryValidationException(
    this.failure, {
    this.textFailure,
  });

  final IntentionCatalogQueryValidationFailure failure;
  final IntentionTextValidationFailure? textFailure;
}

/// Соединяет охват, готовность, название, собственные теги и исключение
/// участника через «И». Условия не требуют существования выбранных тегов.
final class IntentionCatalogQuery {
  factory IntentionCatalogQuery({
    required IntentionScope scope,
    IntentionReadinessFilter readinessFilter = IntentionReadinessFilter.all,
    required String? titleFilter,
    IntentionTagFilter tagFilter = IntentionTagFilter.empty,
    IntentionId? excludedIntentionId,
    required IntentionCatalogOrder order,
    required int pageSize,
    IntentionCatalogCursor? cursor,
    IntentionCatalogCounting counting = IntentionCatalogCounting.totalOnly,
  }) {
    if (pageSize < minPageSize || pageSize > maxPageSize) {
      throw const IntentionCatalogQueryValidationException(
        IntentionCatalogQueryValidationFailure.pageSizeOutOfRange,
      );
    }

    final normalizedFilter = _normalizeFilter(titleFilter);
    return IntentionCatalogQuery._(
      scope: scope,
      readinessFilter: readinessFilter,
      titleFilter: normalizedFilter,
      tagFilter: tagFilter,
      excludedIntentionId: excludedIntentionId,
      order: order,
      pageSize: pageSize,
      cursor: cursor,
      counting: counting,
    );
  }

  const IntentionCatalogQuery._({
    required this.scope,
    required this.readinessFilter,
    required this.titleFilter,
    required this.tagFilter,
    required this.excludedIntentionId,
    required this.order,
    required this.pageSize,
    required this.cursor,
    required this.counting,
  });

  static const minPageSize = 1;
  static const maxPageSize = 100;
  static const maxTitleFilterLength = 255;

  final IntentionScope scope;
  final IntentionReadinessFilter readinessFilter;
  final IntentionTitleFilter? titleFilter;
  final IntentionTagFilter tagFilter;

  /// Второй участник связи, исключаемый по идентичности до подсчёта и порции.
  final IntentionId? excludedIntentionId;
  final IntentionCatalogOrder order;
  final int pageSize;
  final IntentionCatalogCursor? cursor;

  /// Просит первую порцию нести числа вида [counting].
  final IntentionCatalogCounting counting;

  /// Тот же запрос с условием готовности «все»: по нему считаются числа
  /// обоих типов.
  IntentionCatalogQuery withAnyReadiness() => IntentionCatalogQuery._(
    scope: scope,
    readinessFilter: IntentionReadinessFilter.all,
    titleFilter: titleFilter,
    tagFilter: tagFilter,
    excludedIntentionId: excludedIntentionId,
    order: order,
    pageSize: pageSize,
    cursor: cursor,
    counting: counting,
  );

  bool includes(IntentionSummary summary) {
    final matchesScope = switch (scope) {
      IntentionScope.active =>
        summary.archiveState == IntentionArchiveState.active,
      IntentionScope.archived =>
        summary.archiveState == IntentionArchiveState.archived,
      IntentionScope.all => true,
    };
    final matchesReadiness = switch (readinessFilter) {
      IntentionReadinessFilter.all => true,
      IntentionReadinessFilter.readyOnly =>
        summary.readiness == IntentionReadiness.ready,

      IntentionReadinessFilter.notReadyOnly =>
        summary.readiness == IntentionReadiness.notReady,
    };
    if (!matchesScope ||
        !matchesReadiness ||
        summary.id == excludedIntentionId ||
        !tagFilter.matches(summary.tags.map((tag) => tag.id).toSet())) {
      return false;
    }
    return titleFilter?.matchesTitle(summary.title) ?? true;
  }

  /// Порядок выдачи: значение поля в выбранном направлении, при равенстве —
  /// возрастающий идентификатор. Название сравнивается ключами сохранённой
  /// поисковой проекции, как его упорядочивает адаптер.
  int compare(IntentionSummary left, IntentionSummary right) {
    final fieldComparison = switch (order.field) {
      IntentionCatalogSortField.createdAt => left.createdAt.value.compareTo(
        right.createdAt.value,
      ),
      IntentionCatalogSortField.updatedAt => left.updatedAt.value.compareTo(
        right.updatedAt.value,
      ),
      IntentionCatalogSortField.title => left.titleOrderKey.compareTo(
        right.titleOrderKey,
      ),
    };
    final directionAdjusted = switch (order.direction) {
      IntentionCatalogSortDirection.ascending => fieldComparison,
      IntentionCatalogSortDirection.descending => -fieldComparison,
    };
    return directionAdjusted != 0
        ? directionAdjusted
        : left.id.compareTo(right.id);
  }

  static IntentionTitleFilter? _normalizeFilter(String? value) {
    if (value == null) {
      return null;
    }
    try {
      IntentionText.ensureValidUnicodeRepertoire(
        value,
        field: IntentionTextField.titleFilter,
      );
    } on IntentionTextValidationException catch (error) {
      throw IntentionCatalogQueryValidationException(
        IntentionCatalogQueryValidationFailure.invalidUnicodeRepertoire,
        textFailure: error.failure,
      );
    }
    final normalized = value.trim();
    if (normalized.isEmpty) {
      return null;
    }
    if (IntentionText.countGraphemeClusters(normalized) >
        maxTitleFilterLength) {
      throw const IntentionCatalogQueryValidationException(
        IntentionCatalogQueryValidationFailure.titleFilterTooLong,
      );
    }
    return IntentionTitleFilter._(normalized);
  }
}

final class IntentionTitleFilter {
  const IntentionTitleFilter._(this._normalizedValue);

  final String _normalizedValue;

  bool matchesTitle(String title) {
    IntentionText.ensureValidUnicodeRepertoire(
      title,
      field: IntentionTextField.title,
    );
    return titleSearchKey(title).contains(titleSearchKey(_normalizedValue));
  }

  T map<T>(T Function(String normalizedValue) transform) =>
      transform(_normalizedValue);
}

abstract interface class IntentionCatalogCursor {}

/// Непрозрачный ключ порядка названия намерения (ADR-0045).
///
/// Ключ строят адаптеры репозитория из сохранённой поисковой проекции
/// названия, по которой они упорядочивают порции. Содержимое ключа не
/// раскрывается: его можно только сравнить с другим ключом по кодовым точкам,
/// как SQLite сравнивает `TEXT` в `BINARY`.
final class IntentionTitleOrderKey
    implements Comparable<IntentionTitleOrderKey> {
  const IntentionTitleOrderKey.fromSearchProjection(this._searchProjection);

  final String _searchProjection;

  @override
  int compareTo(IntentionTitleOrderKey other) {
    final left = _searchProjection.runes.iterator;
    final right = other._searchProjection.runes.iterator;
    while (true) {
      final hasLeft = left.moveNext();
      final hasRight = right.moveNext();
      if (!hasLeft || !hasRight) {
        return (hasLeft ? 1 : 0) - (hasRight ? 1 : 0);
      }
      final comparison = left.current.compareTo(right.current);
      if (comparison != 0) return comparison;
    }
  }
}

final class IntentionSummary {
  IntentionSummary({
    required this.id,
    required String title,
    required this.descriptionPreview,
    required this.readiness,
    required this.archiveState,
    required this.createdAt,
    required this.updatedAt,
    required this.titleOrderKey,
    List<Tag> tags = const [],
  }) : title = IntentionText.normalizeTitle(title),
       tags = List.unmodifiable(tags);

  final IntentionId id;
  final String title;

  /// Начало описания; `null` означает отсутствие описания.
  final TextPreview? descriptionPreview;
  final IntentionReadiness readiness;
  final IntentionArchiveState archiveState;
  final IntentionTimestamp createdAt;
  final IntentionTimestamp updatedAt;

  /// Ключ порядка по названию из сохранённой поисковой проекции [title].
  final IntentionTitleOrderKey titleOrderKey;

  /// Полный подтверждённый состав собственных тегов в ручном порядке тегов.
  /// Пустой список означает проверенное отсутствие назначений.
  final List<Tag> tags;

  /// Заменяет полное состояние назначенного тега той же идентичности:
  /// название, цвет и место, и упорядочивает теги по месту.
  ///
  /// Состав тегов переносится без изменений, поэтому соответствие фильтру,
  /// порядок выдачи и временные метки сохраняются. Если тег не назначен
  /// намерению, возвращается та же сводка.
  IntentionSummary withUpdatedTag(Tag updated) {
    if (!tags.any((tag) => tag.id == updated.id)) {
      return this;
    }
    return IntentionSummary(
      id: id,
      title: title,
      descriptionPreview: descriptionPreview,
      readiness: readiness,
      archiveState: archiveState,
      createdAt: createdAt,
      updatedAt: updatedAt,
      titleOrderKey: titleOrderKey,
      // Места уникальны, поэтому нестабильная сортировка однозначна.
      tags: [for (final tag in tags) tag.id == updated.id ? updated : tag]
        ..sort((a, b) => a.position.compareTo(b.position)),
    );
  }

  /// Убирает назначение физически удалённого тега.
  ///
  /// Порядок остальных тегов и временные метки сохраняются. Если тег не
  /// назначен намерению, возвращается та же сводка.
  IntentionSummary withoutTag(TagId deletedTagId) {
    if (!tags.any((tag) => tag.id == deletedTagId)) {
      return this;
    }
    return IntentionSummary(
      id: id,
      title: title,
      descriptionPreview: descriptionPreview,
      readiness: readiness,
      archiveState: archiveState,
      createdAt: createdAt,
      updatedAt: updatedAt,
      titleOrderKey: titleOrderKey,
      tags: [
        for (final tag in tags)
          if (tag.id != deletedTagId) tag,
      ],
    );
  }
}

abstract interface class IntentionCatalogEntrySnapshot {
  IntentionSummary get summary;

  bool matches(IntentionCatalogQuery query);
}

sealed class IntentionCatalogMutation implements GraphChange {
  const IntentionCatalogMutation({required this.revision});

  @override
  final GraphRevision revision;

  IntentionCatalogEntrySnapshot? get before;

  IntentionCatalogEntrySnapshot? get after;
}

final class IntentionCatalogCreated extends IntentionCatalogMutation {
  const IntentionCatalogCreated({required super.revision, required this.entry});

  final IntentionCatalogEntrySnapshot entry;

  @override
  IntentionCatalogEntrySnapshot? get before => null;

  @override
  IntentionCatalogEntrySnapshot get after => entry;
}

final class IntentionCatalogUpdated extends IntentionCatalogMutation {
  const IntentionCatalogUpdated({
    required super.revision,
    required this.before,
    required this.after,
  });

  @override
  final IntentionCatalogEntrySnapshot before;

  @override
  final IntentionCatalogEntrySnapshot after;
}

final class IntentionCatalogDeleted extends IntentionCatalogMutation {
  const IntentionCatalogDeleted({required super.revision, required this.entry});

  final IntentionCatalogEntrySnapshot entry;

  @override
  IntentionCatalogEntrySnapshot get before => entry;

  @override
  IntentionCatalogEntrySnapshot? get after => null;
}

final class IntentionCatalogUnchanged extends IntentionCatalogMutation {
  const IntentionCatalogUnchanged({
    required super.revision,
    required this.entry,
  });

  final IntentionCatalogEntrySnapshot entry;

  @override
  IntentionCatalogEntrySnapshot get before => entry;

  @override
  IntentionCatalogEntrySnapshot get after => entry;
}

sealed class IntentionCommandSuccess implements GraphCommandOutcome {
  IntentionCommandSuccess({
    required this.catalogMutation,
    Iterable<IntentionCatalogMutation> additionalCatalogMutations = const [],
    Iterable<GraphChange> additionalChanges = const [],
  }) : catalogMutations = List.unmodifiable([
         catalogMutation,
         ...additionalCatalogMutations,
       ]),
       additionalChanges = List.unmodifiable(additionalChanges);

  final IntentionCatalogMutation catalogMutation;
  final List<IntentionCatalogMutation> catalogMutations;
  final List<GraphChange> additionalChanges;

  @override
  Iterable<GraphChange> get changes =>
      List.unmodifiable([...catalogMutations, ...additionalChanges]);
}

/// Подтверждённый результат сохранения намерения.
///
/// Для `CreateIntention` это единственный окончательный результат всего
/// создания: [catalogMutation] — одна [IntentionCatalogCreated] с полным
/// снимком нового намерения, включая теги и готовность, а
/// [additionalChanges] несут по одному `TagAssignmentChangedChange` на каждое
/// созданное назначение. Все факты принадлежат одной новой ревизии; отдельных
/// результатов готовности или назначений создание не порождает.
final class IntentionSaved extends IntentionCommandSuccess {
  IntentionSaved(
    this.intention, {
    required super.catalogMutation,
    super.additionalCatalogMutations,
    super.additionalChanges,
  });

  final Intention intention;
}

final class IntentionDeleted extends IntentionCommandSuccess {
  IntentionDeleted(
    this.id, {
    required super.catalogMutation,
    super.additionalCatalogMutations,
    super.additionalChanges,
  });

  final IntentionId id;
}

sealed class IntentionCatalogPage {
  IntentionCatalogPage({
    required List<IntentionSummary> items,
    required this.nextCursor,
    required this.revision,
  }) : items = List.unmodifiable(items);

  final List<IntentionSummary> items;
  final IntentionCatalogCursor? nextCursor;
  final GraphRevision revision;
}

final class IntentionCatalogFirstPage extends IntentionCatalogPage {
  IntentionCatalogFirstPage({
    required super.items,
    required int totalCount,
    this.counts = const IntentionCountsTotalOnly(),
    required super.nextCursor,
    required super.revision,
  }) : totalCount = _requireTotalCount(totalCount, items.length, counts);

  /// Количество совпадений со всеми условиями запроса, включая готовность.
  final int totalCount;

  /// Числа вида, который попросил запрос.
  final IntentionCatalogCounts counts;

  static int _requireTotalCount(
    int totalCount,
    int itemCount,
    IntentionCatalogCounts counts,
  ) {
    if (totalCount < itemCount || !counts.admitsTotalCount(totalCount)) {
      throw const IntentionCatalogPageValidationException();
    }
    return totalCount;
  }
}

/// Числа первой порции каталога сверх общего количества.
sealed class IntentionCatalogCounts {
  const IntentionCatalogCounts();

  /// Общее количество не может превышать число всех намерений в этих числах.
  bool admitsTotalCount(int totalCount);
}

/// Порция несёт только общее количество.
final class IntentionCountsTotalOnly extends IntentionCatalogCounts {
  const IntentionCountsTotalOnly();

  @override
  bool admitsTotalCount(int totalCount) => true;
}

/// Числа типов в охвате запроса.
final class IntentionCountsByType extends IntentionCatalogCounts {
  const IntentionCountsByType(this.counts);

  final IntentionTypeCounts counts;

  @override
  bool admitsTotalCount(int totalCount) => totalCount <= counts.all;
}

/// Числа типов отдельно в активном и архивном охватах.
final class IntentionCountsByScopeAndType extends IntentionCatalogCounts {
  const IntentionCountsByScopeAndType({
    required this.active,
    required this.archived,
  });

  final IntentionTypeCounts active;
  final IntentionTypeCounts archived;

  /// Число всех намерений в обоих охватах.
  int get all => active.all + archived.all;

  /// Числа типов в [scope]: для охвата «все» — сумма обоих охватов.
  IntentionTypeCounts inScope(IntentionScope scope) => switch (scope) {
    IntentionScope.active => active,
    IntentionScope.archived => archived,
    IntentionScope.all => IntentionTypeCounts(
      all: all,
      actions: active.actions + archived.actions,
    ),
  };

  @override
  bool admitsTotalCount(int totalCount) => totalCount <= all;
}

/// Точные числа обоих типов намерения в одном охвате при всех условиях запроса,
/// кроме условия готовности.
final class IntentionTypeCounts {
  factory IntentionTypeCounts({required int all, required int actions}) {
    if (actions < 0 || actions > all) {
      throw const IntentionCatalogPageValidationException();
    }
    return IntentionTypeCounts._(all: all, actions: actions);
  }

  const IntentionTypeCounts._({required this.all, required this.actions});

  final int all;
  final int actions;

  int get intentions => all - actions;

  /// Число намерений того типа, который выбирает условие готовности.
  int matching(IntentionReadinessFilter readinessFilter) =>
      switch (readinessFilter) {
        IntentionReadinessFilter.all => all,
        IntentionReadinessFilter.readyOnly => actions,
        IntentionReadinessFilter.notReadyOnly => intentions,
      };
}

final class IntentionCatalogPageValidationException implements Exception {
  const IntentionCatalogPageValidationException();
}

final class IntentionCatalogContinuationPage extends IntentionCatalogPage {
  IntentionCatalogContinuationPage({
    required super.items,
    required super.nextCursor,
    required super.revision,
  });
}
