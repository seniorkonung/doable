import '../../../graph/application/graph_command_coordinator.dart';
import '../../../graph/application/graph_revision.dart';
import '../../application/daily_choice_catalog.dart';
import '../../application/daily_choice_result.dart';
import '../../domain/calendar_date.dart';
import '../../domain/daily_choice_id.dart';
import 'daily_choice_catalog_snapshot_assembly.dart';

/// Выбранный день и независимое раскрытие секций принадлежат экземпляру.
final class DailyChoiceCatalogSelection {
  const DailyChoiceCatalogSelection({
    required this.date,
    this.incompleteExpanded = true,
    this.completedExpanded = false,
  });

  final CalendarDate date;
  final bool incompleteExpanded;
  final bool completedExpanded;

  bool isExpanded(bool isCompleted) =>
      isCompleted ? completedExpanded : incompleteExpanded;

  DailyChoiceCatalogSelection withDate(CalendarDate value) =>
      DailyChoiceCatalogSelection(
        date: value,
        incompleteExpanded: incompleteExpanded,
        completedExpanded: completedExpanded,
      );

  DailyChoiceCatalogSelection toggle(bool isCompleted) =>
      DailyChoiceCatalogSelection(
        date: date,
        incompleteExpanded: isCompleted
            ? incompleteExpanded
            : !incompleteExpanded,
        completedExpanded: isCompleted ? !completedExpanded : completedExpanded,
      );
}

sealed class DailyChoiceCatalogState {
  const DailyChoiceCatalogState(
    this.selection, {
    this.completionOperations = const {},
  });
  final DailyChoiceCatalogSelection selection;
  final Map<DailyChoiceId, DailyChoiceCompletionOperation> completionOperations;

  bool canChangeCompletion(DailyChoiceId id) => switch (this) {
    DailyChoiceCatalogLoaded(:final items)
        when items.any((item) => item.id == id) =>
      switch (completionOperations[id]) {
        null || DailyChoiceCompletionFailed(canRetry: true) => true,
        _ => false,
      },
    _ => false,
  };

  DailyChoiceCatalogState withCompletionOperations(
    Map<DailyChoiceId, DailyChoiceCompletionOperation> operations,
  ) {
    final immutable =
        Map<DailyChoiceId, DailyChoiceCompletionOperation>.unmodifiable(
          operations,
        );
    return switch (this) {
      DailyChoiceCatalogInitialLoad() => DailyChoiceCatalogInitialLoad(
        selection,
        completionOperations: immutable,
      ),
      DailyChoiceCatalogInitialFailure(:final failure) =>
        DailyChoiceCatalogInitialFailure(
          selection,
          failure,
          completionOperations: immutable,
        ),
      DailyChoiceCatalogLoaded loaded => loaded.withStatus(
        completionOperations: immutable,
        refreshFailure: loaded.refreshFailure,
      ),
    };
  }
}

final class DailyChoiceCatalogInitialLoad extends DailyChoiceCatalogState {
  const DailyChoiceCatalogInitialLoad(
    super.selection, {
    super.completionOperations,
  });
}

final class DailyChoiceCatalogInitialFailure extends DailyChoiceCatalogState {
  const DailyChoiceCatalogInitialFailure(
    super.selection,
    this.failure, {
    super.completionOperations,
  });
  final DailyChoiceCatalogReadFailure failure;
  bool get canRetry => failure is DailyChoiceCatalogUnavailableFailure;
}

enum DailyChoiceCatalogFreshness { current, refreshing, stale }

sealed class DailyChoiceCompletionOperation {
  const DailyChoiceCompletionOperation();
}

final class DailyChoiceCompletionSubmitting
    extends DailyChoiceCompletionOperation {
  const DailyChoiceCompletionSubmitting();
}

final class DailyChoiceCompletionAwaitingSnapshot
    extends DailyChoiceCompletionOperation {
  const DailyChoiceCompletionAwaitingSnapshot(this.revision);
  final GraphRevision revision;
}

final class DailyChoiceCompletionFailed extends DailyChoiceCompletionOperation {
  const DailyChoiceCompletionFailed(this.failure, {this.inline});
  final DailyChoiceCommandFailure failure;

  /// Сообщение у карточки; без него отказ предъявляет общая поверхность.
  final DailyChoiceCompletionInlineFailure? inline;
  bool get canRetry => failure is DailyChoiceUnavailableFailure;

  /// Без явного повтора флажок возвращает только актуальная пара.
  bool get requiresRefresh => !canRetry;
}

/// Отказ, который карточка предъявляет только в получившей его сессии.
final class DailyChoiceCompletionInlineFailure {
  const DailyChoiceCompletionInlineFailure(this.session, {this.claim});
  final DailyChoiceCompletionSession session;

  /// Право принятой команды; отклонённое до принятия изменение его не имеет.
  final GraphInitiatorPresentationClaim? claim;
}

/// Экранная сессия карточки, начавшей изменение выполнения.
///
/// Удаление карточки и уход с её экрана закрывают сессию навсегда, поэтому
/// вернувшаяся карточка не повторяет отказ, уже предъявленный у неё или
/// переданный общей поверхности.
final class DailyChoiceCompletionSession {
  DailyChoiceCompletionSession({required this._isCurrent});

  final bool Function() _isCurrent;
  var _isOpen = true;

  bool get isOpen => _isOpen;

  /// Отказ, полученный сейчас, можно предъявить у карточки.
  bool get canPresentFailure => _isOpen && _isCurrent();

  void close() => _isOpen = false;
}

sealed class DailyChoiceCatalogPageStatus {
  const DailyChoiceCatalogPageStatus();
}

final class DailyChoiceCatalogPageIdle extends DailyChoiceCatalogPageStatus {
  const DailyChoiceCatalogPageIdle();
}

final class DailyChoiceCatalogPageLoading extends DailyChoiceCatalogPageStatus {
  const DailyChoiceCatalogPageLoading();
}

final class DailyChoiceCatalogPageFailure extends DailyChoiceCatalogPageStatus {
  const DailyChoiceCatalogPageFailure(this.failure);
  final DailyChoiceCatalogReadFailure failure;
  bool get canRetry => failure is DailyChoiceCatalogUnavailableFailure;
}

/// Сводка и продолжение одной секции на общей ревизии каталога.
final class DailyChoiceCatalogSectionState {
  DailyChoiceCatalogSectionState.fromSnapshot(
    DailyChoiceCatalogSectionSnapshot snapshot,
  ) : this._(
        items: snapshot.items,
        totalCount: snapshot.totalCount,
        hasTimedChoices: snapshot.hasTimedChoices,
        nextCursor: snapshot.nextCursor,
      );

  DailyChoiceCatalogSectionState._({
    required List<DailyChoiceCatalogItem> items,
    required this.totalCount,
    required this.hasTimedChoices,
    required this.nextCursor,
    this.pageStatus = const DailyChoiceCatalogPageIdle(),
  }) : items = List.unmodifiable(items);

  final List<DailyChoiceCatalogItem> items;
  final int totalCount;
  final bool hasTimedChoices;
  final DailyChoiceCatalogCursor? nextCursor;
  final DailyChoiceCatalogPageStatus pageStatus;

  DailyChoiceCatalogSectionState withStatus(
    DailyChoiceCatalogPageStatus status,
  ) => DailyChoiceCatalogSectionState._(
    items: items,
    totalCount: totalCount,
    hasTimedChoices: hasTimedChoices,
    nextCursor: nextCursor,
    pageStatus: status,
  );

  DailyChoiceCatalogSectionState append(
    DailyChoiceCatalogContinuationPage page,
  ) => DailyChoiceCatalogSectionState._(
    items: [...items, ...page.items],
    totalCount: totalCount,
    hasTimedChoices: hasTimedChoices,
    nextCursor: page.nextCursor,
  );
}

/// Обе секции публикуются вместе; актуальность и ревизия принадлежат паре.
final class DailyChoiceCatalogLoaded extends DailyChoiceCatalogState {
  DailyChoiceCatalogLoaded.fromSnapshot({
    required DailyChoiceCatalogSelection selection,
    required DailyChoiceCatalogSnapshot snapshot,
    Map<DailyChoiceId, DailyChoiceCompletionOperation> completionOperations =
        const {},
  }) : this._(
         selection: selection,
         completionOperations: completionOperations,
         incomplete: DailyChoiceCatalogSectionState.fromSnapshot(
           snapshot.incomplete,
         ),
         completed: DailyChoiceCatalogSectionState.fromSnapshot(
           snapshot.completed,
         ),
         revision: snapshot.revision,
       );

  const DailyChoiceCatalogLoaded._({
    required DailyChoiceCatalogSelection selection,
    required this.incomplete,
    required this.completed,
    required this.revision,
    this.freshness = DailyChoiceCatalogFreshness.current,
    this.refreshFailure,
    this.needsRebase = false,
    Map<DailyChoiceId, DailyChoiceCompletionOperation> completionOperations =
        const {},
  }) : super(selection, completionOperations: completionOperations);

  final DailyChoiceCatalogSectionState incomplete;
  final DailyChoiceCatalogSectionState completed;
  final GraphRevision revision;
  final DailyChoiceCatalogFreshness freshness;
  final DailyChoiceCatalogReadFailure? refreshFailure;
  final bool needsRebase;

  int get totalCount => incomplete.totalCount + completed.totalCount;
  Iterable<DailyChoiceCatalogItem> get items => [
    ...incomplete.items,
    ...completed.items,
  ];
  DailyChoiceCatalogSectionState section(bool isCompleted) =>
      isCompleted ? completed : incomplete;

  DailyChoiceCatalogLoaded withStatus({
    DailyChoiceCatalogSelection? selection,
    DailyChoiceCatalogSectionState? incomplete,
    DailyChoiceCatalogSectionState? completed,
    DailyChoiceCatalogFreshness? freshness,
    DailyChoiceCatalogReadFailure? refreshFailure,
    bool? needsRebase,
    Map<DailyChoiceId, DailyChoiceCompletionOperation>? completionOperations,
  }) => DailyChoiceCatalogLoaded._(
    selection: selection ?? this.selection,
    completionOperations: completionOperations ?? this.completionOperations,
    incomplete: incomplete ?? this.incomplete,
    completed: completed ?? this.completed,
    revision: revision,
    freshness: freshness ?? this.freshness,
    refreshFailure: refreshFailure,
    needsRebase: needsRebase ?? this.needsRebase,
  );

  DailyChoiceCatalogLoaded withSection(
    bool isCompleted,
    DailyChoiceCatalogSectionState section,
  ) => withStatus(
    incomplete: isCompleted ? null : section,
    completed: isCompleted ? section : null,
    refreshFailure: refreshFailure,
  );
}
