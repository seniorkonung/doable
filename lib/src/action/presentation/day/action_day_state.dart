import '../../../graph/application/graph_command_coordinator.dart';
import '../../../graph/application/graph_revision.dart';
import '../../../shared/domain/calendar_date.dart';
import '../../application/action_day.dart';
import '../../application/action_list_item.dart';
import '../../application/action_result.dart';
import '../../domain/action_id.dart';
import 'action_day_snapshot_assembly.dart';

/// Выбранный день и независимое раскрытие секций принадлежат экземпляру.
final class ActionDaySelection {
  const ActionDaySelection({
    required this.date,
    this.incompleteExpanded = true,
    this.completedExpanded = true,
  });

  final CalendarDate date;
  final bool incompleteExpanded;
  final bool completedExpanded;

  bool isExpanded(ActionDaySection section) => switch (section) {
    ActionDaySection.incomplete => incompleteExpanded,
    ActionDaySection.completed => completedExpanded,
  };

  ActionDaySelection withDate(CalendarDate value) => ActionDaySelection(
    date: value,
    incompleteExpanded: incompleteExpanded,
    completedExpanded: completedExpanded,
  );

  ActionDaySelection toggle(ActionDaySection section) => ActionDaySelection(
    date: date,
    incompleteExpanded: switch (section) {
      ActionDaySection.incomplete => !incompleteExpanded,
      ActionDaySection.completed => incompleteExpanded,
    },
    completedExpanded: switch (section) {
      ActionDaySection.incomplete => completedExpanded,
      ActionDaySection.completed => !completedExpanded,
    },
  );
}

sealed class ActionDayState {
  const ActionDayState(this.selection, {this.completionOperations = const {}});
  final ActionDaySelection selection;
  final Map<ActionId, ActionCompletionOperation> completionOperations;

  bool canChangeCompletion(ActionId id) => switch (this) {
    ActionDayLoaded(:final items) when items.any((item) => item.id == id) =>
      switch (completionOperations[id]) {
        null || ActionCompletionFailed(canRetry: true) => true,
        _ => false,
      },
    _ => false,
  };

  ActionDayState withCompletionOperations(
    Map<ActionId, ActionCompletionOperation> operations,
  ) {
    final immutable = Map<ActionId, ActionCompletionOperation>.unmodifiable(
      operations,
    );
    return switch (this) {
      ActionDayInitialLoad() => ActionDayInitialLoad(
        selection,
        completionOperations: immutable,
      ),
      ActionDayInitialFailure(:final failure) => ActionDayInitialFailure(
        selection,
        failure,
        completionOperations: immutable,
      ),
      ActionDayLoaded loaded => loaded.withStatus(
        completionOperations: immutable,
        refreshFailure: loaded.refreshFailure,
      ),
    };
  }
}

final class ActionDayInitialLoad extends ActionDayState {
  const ActionDayInitialLoad(super.selection, {super.completionOperations});
}

final class ActionDayInitialFailure extends ActionDayState {
  const ActionDayInitialFailure(
    super.selection,
    this.failure, {
    super.completionOperations,
  });
  final ActionDayReadFailure failure;
  bool get canRetry => failure is ActionDayUnavailableFailure;
}

enum ActionDayFreshness { current, refreshing, stale }

sealed class ActionCompletionOperation {
  const ActionCompletionOperation();
}

final class ActionCompletionSubmitting extends ActionCompletionOperation {
  const ActionCompletionSubmitting();
}

final class ActionCompletionAwaitingSnapshot extends ActionCompletionOperation {
  const ActionCompletionAwaitingSnapshot(this.revision);
  final GraphRevision revision;
}

final class ActionCompletionFailed extends ActionCompletionOperation {
  const ActionCompletionFailed(this.failure, {this.inline});
  final ActionCommandFailure failure;

  /// Сообщение у строки; без него отказ предъявляет общая поверхность.
  final ActionCompletionInlineFailure? inline;
  bool get canRetry => failure is ActionUnavailableFailure;

  /// Без явного повтора флажок возвращает только актуальная пара.
  bool get requiresRefresh => !canRetry;
}

/// Отказ, который строка предъявляет только в получившей его сессии.
final class ActionCompletionInlineFailure {
  const ActionCompletionInlineFailure(this.session, {this.claim});
  final ActionCompletionSession session;

  /// Право принятой команды; отклонённое до принятия изменение его не имеет.
  final GraphInitiatorPresentationClaim? claim;
}

/// Экранная сессия строки, начавшей изменение выполнения.
///
/// Удаление строки и уход с её экрана закрывают сессию навсегда, поэтому
/// вернувшаяся строка не повторяет отказ, уже предъявленный у неё или
/// переданный общей поверхности.
final class ActionCompletionSession {
  ActionCompletionSession({required this._isCurrent});

  final bool Function() _isCurrent;
  var _isOpen = true;

  bool get isOpen => _isOpen;

  /// Отказ, полученный сейчас, можно предъявить у строки.
  bool get canPresentFailure => _isOpen && _isCurrent();

  void close() => _isOpen = false;
}

sealed class ActionDayContinuationStatus {
  const ActionDayContinuationStatus();
}

final class ActionDayContinuationIdle extends ActionDayContinuationStatus {
  const ActionDayContinuationIdle();
}

final class ActionDayContinuationLoading extends ActionDayContinuationStatus {
  const ActionDayContinuationLoading();
}

final class ActionDayContinuationFailure extends ActionDayContinuationStatus {
  const ActionDayContinuationFailure(this.failure);
  final ActionDayReadFailure failure;
  bool get canRetry => failure is ActionDayUnavailableFailure;
}

/// Число действий и продолжение одной секции на общей ревизии выдачи.
final class ActionDaySectionState {
  ActionDaySectionState.fromSnapshot(ActionDaySectionSnapshot snapshot)
    : this._(
        items: snapshot.items,
        totalCount: snapshot.totalCount,
        nextCursor: snapshot.nextCursor,
      );

  ActionDaySectionState._({
    required List<ActionListItem> items,
    required this.totalCount,
    required this.nextCursor,
    this.pageStatus = const ActionDayContinuationIdle(),
  }) : items = List.unmodifiable(items);

  final List<ActionListItem> items;
  final int totalCount;
  final ActionDayCursor? nextCursor;
  final ActionDayContinuationStatus pageStatus;

  ActionDaySectionState withStatus(ActionDayContinuationStatus status) =>
      ActionDaySectionState._(
        items: items,
        totalCount: totalCount,
        nextCursor: nextCursor,
        pageStatus: status,
      );

  ActionDaySectionState append(ActionDayContinuationPage page) =>
      ActionDaySectionState._(
        items: [...items, ...page.items],
        totalCount: totalCount,
        nextCursor: page.nextCursor,
      );
}

/// Обе секции публикуются вместе; актуальность и ревизия принадлежат паре.
final class ActionDayLoaded extends ActionDayState {
  ActionDayLoaded.fromSnapshot({
    required ActionDaySelection selection,
    required ActionDaySnapshot snapshot,
    Map<ActionId, ActionCompletionOperation> completionOperations = const {},
  }) : this._(
         selection: selection,
         completionOperations: completionOperations,
         incomplete: ActionDaySectionState.fromSnapshot(snapshot.incomplete),
         completed: ActionDaySectionState.fromSnapshot(snapshot.completed),
         hasTimedActions: snapshot.hasTimedActions,
         revision: snapshot.revision,
       );

  const ActionDayLoaded._({
    required ActionDaySelection selection,
    required this.incomplete,
    required this.completed,
    required this.hasTimedActions,
    required this.revision,
    this.freshness = ActionDayFreshness.current,
    this.refreshFailure,
    this.needsRebase = false,
    Map<ActionId, ActionCompletionOperation> completionOperations = const {},
  }) : super(selection, completionOperations: completionOperations);

  final ActionDaySectionState incomplete;
  final ActionDaySectionState completed;

  /// Время есть у действия дня в любой секции, в том числе в неполученной
  /// порции.
  final bool hasTimedActions;
  final GraphRevision revision;
  final ActionDayFreshness freshness;
  final ActionDayReadFailure? refreshFailure;
  final bool needsRebase;

  /// Повтор несёт только доказанно временный отказ обновления.
  bool get canRetryRefresh => refreshFailure is ActionDayUnavailableFailure;

  int get totalCount => incomplete.totalCount + completed.totalCount;

  Iterable<ActionListItem> get items => [
    ...incomplete.items,
    ...completed.items,
  ];

  ActionDaySectionState section(ActionDaySection section) => switch (section) {
    ActionDaySection.incomplete => incomplete,
    ActionDaySection.completed => completed,
  };

  ActionDayLoaded withStatus({
    ActionDaySelection? selection,
    ActionDaySectionState? incomplete,
    ActionDaySectionState? completed,
    ActionDayFreshness? freshness,
    ActionDayReadFailure? refreshFailure,
    bool? needsRebase,
    Map<ActionId, ActionCompletionOperation>? completionOperations,
  }) => ActionDayLoaded._(
    selection: selection ?? this.selection,
    completionOperations: completionOperations ?? this.completionOperations,
    incomplete: incomplete ?? this.incomplete,
    completed: completed ?? this.completed,
    hasTimedActions: hasTimedActions,
    revision: revision,
    freshness: freshness ?? this.freshness,
    refreshFailure: refreshFailure,
    needsRebase: needsRebase ?? this.needsRebase,
  );

  ActionDayLoaded withSection(
    ActionDaySection section,
    ActionDaySectionState state,
  ) => withStatus(
    incomplete: section == ActionDaySection.incomplete ? state : null,
    completed: section == ActionDaySection.completed ? state : null,
    refreshFailure: refreshFailure,
  );
}
