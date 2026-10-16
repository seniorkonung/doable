import '../../../graph/application/graph_revision.dart';
import '../../application/daily_choice_catalog.dart';
import '../../domain/calendar_date.dart';
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
  const DailyChoiceCatalogState(this.selection);
  final DailyChoiceCatalogSelection selection;
}

final class DailyChoiceCatalogInitialLoad extends DailyChoiceCatalogState {
  const DailyChoiceCatalogInitialLoad(super.selection);
}

final class DailyChoiceCatalogInitialFailure extends DailyChoiceCatalogState {
  const DailyChoiceCatalogInitialFailure(super.selection, this.failure);
  final DailyChoiceCatalogReadFailure failure;
  bool get canRetry => failure is DailyChoiceCatalogUnavailableFailure;
}

enum DailyChoiceCatalogFreshness { current, refreshing, stale }

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
  }) : this._(
         selection: selection,
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
  }) : super(selection);

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
  }) => DailyChoiceCatalogLoaded._(
    selection: selection ?? this.selection,
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
