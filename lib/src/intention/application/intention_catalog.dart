import '../../graph/application/graph_revision.dart';
import '../../tag/domain/tag.dart';
import '../../tag/domain/tag_id.dart';
import '../domain/intention.dart';
import '../domain/intention_id.dart';
import '../domain/intention_text.dart';
import 'title_search_key.dart';

enum IntentionScope { active, archived, all }

enum IntentionReadinessFilter { all, readyOnly }

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

enum IntentionCatalogSortField { createdAt, updatedAt }

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
    };
    if (!matchesScope ||
        !matchesReadiness ||
        summary.id == excludedIntentionId ||
        !tagFilter.matches(summary.tags.map((tag) => tag.id).toSet())) {
      return false;
    }
    return titleFilter?.matchesTitle(summary.title) ?? true;
  }

  int compare(IntentionSummary left, IntentionSummary right) {
    final timestampComparison = _timestampOf(left).value
        .compareTo(_timestampOf(right).value);
    final directionAdjusted = switch (order.direction) {
      IntentionCatalogSortDirection.ascending => timestampComparison,
      IntentionCatalogSortDirection.descending => -timestampComparison,
    };
    return directionAdjusted != 0
        ? directionAdjusted
        : left.id.compareTo(right.id);
  }

  IntentionTimestamp _timestampOf(IntentionSummary summary) =>
      switch (order.field) {
        IntentionCatalogSortField.createdAt => summary.createdAt,
        IntentionCatalogSortField.updatedAt => summary.updatedAt,
      };

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

final class IntentionSummary {
  IntentionSummary({
    required this.id,
    required String title,
    required this.hasDescription,
    required this.readiness,
    required this.archiveState,
    required int activeRelationCount,
    required this.createdAt,
    required this.updatedAt,
    List<Tag> tags = const [],
  }) : title = IntentionText.normalizeTitle(title),
       activeRelationCount = _requireNonNegativeCount(activeRelationCount),
       tags = List.unmodifiable(tags);

  final IntentionId id;
  final String title;
  final bool hasDescription;
  final IntentionReadiness readiness;
  final IntentionArchiveState archiveState;
  final int activeRelationCount;
  final IntentionTimestamp createdAt;
  final IntentionTimestamp updatedAt;

  /// Полный подтверждённый состав собственных тегов в порядке создания тегов.
  /// Пустой список означает проверенное отсутствие назначений.
  final List<Tag> tags;

  /// Заменяет только производный счётчик активных связей.
  ///
  /// Остальные данные краткого представления переносятся без изменений,
  /// поэтому соответствие фильтру, порядок и временные метки сохраняются.
  IntentionSummary withActiveRelationCount(int activeRelationCount) =>
      IntentionSummary(
        id: id,
        title: title,
        hasDescription: hasDescription,
        readiness: readiness,
        archiveState: archiveState,
        activeRelationCount: activeRelationCount,
        createdAt: createdAt,
        updatedAt: updatedAt,
        tags: tags,
      );

  /// Заменяет название назначенного тега той же идентичности.
  ///
  /// Состав и порядок тегов переносятся без изменений, поэтому соответствие
  /// фильтру, порядок выдачи и временные метки сохраняются. Если тег не
  /// назначен намерению, возвращается та же сводка.
  IntentionSummary withRenamedTag(Tag renamed) {
    if (!tags.any((tag) => tag.id == renamed.id)) {
      return this;
    }
    return IntentionSummary(
      id: id,
      title: title,
      hasDescription: hasDescription,
      readiness: readiness,
      archiveState: archiveState,
      activeRelationCount: activeRelationCount,
      createdAt: createdAt,
      updatedAt: updatedAt,
      tags: [for (final tag in tags) tag.id == renamed.id ? renamed : tag],
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
      hasDescription: hasDescription,
      readiness: readiness,
      archiveState: archiveState,
      activeRelationCount: activeRelationCount,
      createdAt: createdAt,
      updatedAt: updatedAt,
      tags: [
        for (final tag in tags)
          if (tag.id != deletedTagId) tag,
      ],
    );
  }

  static int _requireNonNegativeCount(int value) {
    if (value < 0) {
      throw ArgumentError.value(
        value,
        'activeRelationCount',
        'Количество активных связей не может быть отрицательным.',
      );
    }
    return value;
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
    required super.nextCursor,
    required super.revision,
  }) : totalCount = _requireTotalCount(totalCount, items.length);

  final int totalCount;

  static int _requireTotalCount(int totalCount, int itemCount) {
    if (totalCount < itemCount) {
      throw const IntentionCatalogPageValidationException();
    }
    return totalCount;
  }
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

/// Граница области открытой выдачи, которую согласует чтение согласования.
sealed class IntentionCatalogReconciliationBoundary {
  const IntentionCatalogReconciliationBoundary();
}

/// Частично загруженный префикс заканчивается ключом сортировки обычного
/// продолжения этой выдачи. Совпадения после ключа получает обычное
/// продолжение, а не чтение согласования.
final class IntentionCatalogPartialPrefixBoundary
    extends IntentionCatalogReconciliationBoundary {
  const IntentionCatalogPartialPrefixBoundary(this.continuation);

  final IntentionCatalogCursor continuation;
}

/// Выдача ранее загружена до конца, в том числе пустая: область
/// согласования продолжается до нового конца выдачи.
final class IntentionCatalogCompletedBoundary
    extends IntentionCatalogReconciliationBoundary {
  const IntentionCatalogCompletedBoundary();
}

/// Непрозрачное продолжение одного согласования. Оно связано с запросом,
/// границей области, позицией в действующем порядке, строками своего окна,
/// следующими за позицией, и ревизией первой порции.
abstract interface class IntentionCatalogReconciliationCursor {}

/// Окно сохранённых строк области, следующих за курсором согласования в
/// действующем порядке. Строки окна исключаются из порции по идентичности, а
/// недостающие совпадения читаются не дальше верхнего края окна. Окно больше
/// размера порции запроса отклоняется как недопустимый ввод без чтения.
sealed class IntentionCatalogReconciliationWindow {
  IntentionCatalogReconciliationWindow._(Iterable<IntentionSummary> storedRows)
    : storedRows = List.unmodifiable(storedRows);

  /// Сохранённые строки окна в действующем порядке.
  final List<IntentionSummary> storedRows;

  List<IntentionId> get storedIntentionIds => [
    for (final row in storedRows) row.id,
  ];
}

/// За окном следуют другие сохранённые строки области: верхний край окна —
/// ключ сортировки его последней строки.
final class IntentionCatalogInnerReconciliationWindow
    extends IntentionCatalogReconciliationWindow {
  IntentionCatalogInnerReconciliationWindow(super.storedRows) : super._() {
    if (storedRows.isEmpty) {
      throw ArgumentError.value(
        storedRows,
        'storedRows',
        'Внутреннее окно содержит хотя бы одну сохранённую строку.',
      );
    }
  }

  IntentionSummary get upperEdgeRow => storedRows.last;
}

/// Окно содержит последнюю сохранённую строку области либо пусто, потому что
/// сохранённых строк после курсора нет: верхний край окна — граница области.
final class IntentionCatalogFinalReconciliationWindow
    extends IntentionCatalogReconciliationWindow {
  IntentionCatalogFinalReconciliationWindow(super.storedRows) : super._();
}

/// Запрос недостающих совпадений внутри уже загруженной области.
///
/// [catalogQuery] задаёт текущий совместный фильтр и порядок открытой выдачи
/// без курсора обычного продолжения. Область передаётся не целиком, а
/// скользящим окном сохранённых строк после [cursor]; без курсора окно
/// начинается с первой сохранённой строки области.
final class IntentionCatalogReconciliationQuery {
  const IntentionCatalogReconciliationQuery({
    required this.catalogQuery,
    required this.boundary,
    required this.window,
    this.cursor,
  });

  final IntentionCatalogQuery catalogQuery;
  final IntentionCatalogReconciliationBoundary boundary;
  final IntentionCatalogReconciliationWindow window;
  final IntentionCatalogReconciliationCursor? cursor;
}

/// Исход чтения согласования, отличный от безопасно классифицированного
/// отказа: порция недостающих совпадений либо требование повторить
/// согласование для актуальной ревизии.
sealed class IntentionCatalogReconciliationOutcome {
  const IntentionCatalogReconciliationOutcome();
}

/// Порция недостающих совпадений области в действующем порядке с полным
/// составом собственных тегов. Все порции одного согласования отражают одну
/// ревизию.
///
/// Порция содержит совпадения после курсора и не дальше верхнего края окна.
/// Продолжение заполненной порции начинается с ключа её последней строки,
/// незаполненной порции внутреннего окна — с верхнего края окна. Отсутствие
/// продолжения означает, что окно было последним и совпадений в нём больше
/// нет.
sealed class IntentionCatalogReconciliationPortion
    extends IntentionCatalogReconciliationOutcome {
  IntentionCatalogReconciliationPortion({
    required List<IntentionSummary> items,
    required this.nextCursor,
    required this.revision,
  }) : items = List.unmodifiable(items);

  final List<IntentionSummary> items;
  final IntentionCatalogReconciliationCursor? nextCursor;
  final GraphRevision revision;
}

/// Первая порция согласования несёт абсолютное количество совпадений всего
/// совместного фильтра, не ограниченное областью и сохранёнными строками.
final class IntentionCatalogReconciliationFirstPortion
    extends IntentionCatalogReconciliationPortion {
  IntentionCatalogReconciliationFirstPortion({
    required super.items,
    required int totalCount,
    required super.nextCursor,
    required super.revision,
  }) : totalCount = IntentionCatalogFirstPage._requireTotalCount(
         totalCount,
         items.length,
       );

  final int totalCount;
}

final class IntentionCatalogReconciliationContinuationPortion
    extends IntentionCatalogReconciliationPortion {
  IntentionCatalogReconciliationContinuationPortion({
    required super.items,
    required super.nextCursor,
    required super.revision,
  });
}

/// Граф изменился после первой порции: полученные порции нельзя
/// публиковать, а согласование повторяется для актуальной ревизии.
final class IntentionCatalogReconciliationRetry
    extends IntentionCatalogReconciliationOutcome {
  const IntentionCatalogReconciliationRetry();
}
