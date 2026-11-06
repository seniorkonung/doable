import '../../../graph/application/graph_revision.dart';
import '../../application/action_list_item.dart';
import '../../application/intention_actions.dart';

/// Вкладка «Действия» страницы намерения.
///
/// Числа ролей известны и тогда, когда вкладка не показана: по ним страница
/// называет вкладку, а список выбирает плитку.
sealed class IntentionActionsState {
  const IntentionActionsState();

  /// Последние подтверждённые числа; `null`, пока они ещё не получены.
  IntentionActionCounts? get counts;
}

/// Вкладка не показана: строки не загружены, читаются только числа.
final class IntentionActionsHidden extends IntentionActionsState {
  const IntentionActionsHidden({this.counts});

  @override
  final IntentionActionCounts? counts;
}

/// Первое чтение списка: подтверждённых строк ещё нет.
final class IntentionActionsInitialLoad extends IntentionActionsState {
  const IntentionActionsInitialLoad({this.counts, this.role});

  @override
  final IntentionActionCounts? counts;

  /// Выбранная плитка; `null`, пока она не выбрана и ждёт чисел.
  final IntentionActionRole? role;
}

/// Первое чтение списка завершилось отказом; это не пустой список.
final class IntentionActionsInitialFailure extends IntentionActionsState {
  const IntentionActionsInitialFailure({
    required this.failure,
    this.counts,
    this.role,
  });

  @override
  final IntentionActionCounts? counts;
  final IntentionActionRole? role;
  final IntentionActionsReadFailure failure;

  /// Повтор несёт только доказанно временный отказ.
  bool get canRetry => failure is IntentionActionsUnavailableFailure;
}

/// Подтверждённые числа и загруженная часть списка выбранной плитки на одной
/// ревизии графа.
final class IntentionActionsLoaded extends IntentionActionsState {
  IntentionActionsLoaded({
    required this.role,
    required this.counts,
    required this.revision,
    required List<ActionListItem> items,
    required this.nextCursor,
    this.page = const IntentionActionsPageIdle(),
    this.freshness = const IntentionActionsCurrent(),
  }) : items = List.unmodifiable(items);

  final IntentionActionRole role;
  @override
  final IntentionActionCounts counts;
  final GraphRevision revision;

  /// Загруженная часть в порядке показа.
  final List<ActionListItem> items;
  final IntentionActionsCursor? nextCursor;
  final IntentionActionsPageStatus page;
  final IntentionActionsFreshness freshness;

  bool get isRefreshing => freshness is IntentionActionsRefreshing;

  /// Повтор несёт только доказанно временный отказ обновления.
  bool get canRetryRefresh => switch (freshness) {
    IntentionActionsStale(:final failure) =>
      failure is IntentionActionsUnavailableFailure,
    IntentionActionsCurrent() || IntentionActionsRefreshing() => false,
  };

  IntentionActionsLoaded copyWith({
    IntentionActionsPageStatus? page,
    IntentionActionsFreshness? freshness,
  }) => IntentionActionsLoaded(
    role: role,
    counts: counts,
    revision: revision,
    items: items,
    nextCursor: nextCursor,
    page: page ?? this.page,
    freshness: freshness ?? this.freshness,
  );

  IntentionActionsLoaded appended(IntentionActionsContinuationPage next) =>
      IntentionActionsLoaded(
        role: role,
        counts: counts,
        revision: revision,
        items: [...items, ...next.items],
        nextCursor: next.nextCursor,
        freshness: freshness,
      );
}

/// Подгрузка следующей порции поверх загруженной части.
sealed class IntentionActionsPageStatus {
  const IntentionActionsPageStatus();
}

final class IntentionActionsPageIdle extends IntentionActionsPageStatus {
  const IntentionActionsPageIdle();
}

final class IntentionActionsPageLoading extends IntentionActionsPageStatus {
  const IntentionActionsPageLoading();
}

/// Прежние строки и продолжение сохранены.
final class IntentionActionsPageFailure extends IntentionActionsPageStatus {
  const IntentionActionsPageFailure(this.failure);

  final IntentionActionsReadFailure failure;

  bool get canRetry => failure is IntentionActionsUnavailableFailure;
}

/// Актуальность показанной части относительно подтверждённых изменений.
sealed class IntentionActionsFreshness {
  const IntentionActionsFreshness();
}

final class IntentionActionsCurrent extends IntentionActionsFreshness {
  const IntentionActionsCurrent();
}

/// Прежняя часть показана, пока собирается её замена.
final class IntentionActionsRefreshing extends IntentionActionsFreshness {
  const IntentionActionsRefreshing();
}

/// Замену получить не удалось, поэтому показанная часть устарела.
final class IntentionActionsStale extends IntentionActionsFreshness {
  const IntentionActionsStale(this.failure);

  final IntentionActionsReadFailure failure;
}
