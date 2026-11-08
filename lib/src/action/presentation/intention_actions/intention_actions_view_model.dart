import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../graph/application/graph_change.dart';
import '../../../graph/application/graph_command_coordinator.dart';
import '../../../graph/application/graph_command_result.dart';
import '../../../graph/application/graph_revision.dart';
import '../../../graph/application/personal_graph_repository.dart';
import '../../../graph/application/personal_graph_repository_provider.dart';
import '../../../intention/application/intention_catalog.dart';
import '../../../intention/domain/intention_id.dart';
import '../../../intention/presentation/details/intention_page_target.dart';
import '../../application/intention_actions.dart';
import '../../domain/action.dart';
import 'intention_actions_assembly.dart';
import 'intention_actions_state.dart';

part 'intention_actions_view_model.g.dart';

/// Числа ролей и порции действий намерения, в путях которых оно играет
/// выбранную роль.
///
/// Страница держит модель, пока подробные данные намерения получены, поэтому
/// число вкладки известно и под другими вкладками. Пока вкладка не показана
/// ([setVisible]), модель читает только числа и не держит строк и
/// продолжения. Выбранная плитка остаётся в экземпляре страницы.
///
/// Подтверждённые изменения действий пути намерения и корневых намерений
/// загруженных строк пересобирают числа и загруженную часть на одной
/// ревизии, а прежняя часть остаётся на экране до готовности замены.
// https://riverpod.dev/docs/concepts2/family
// https://riverpod.dev/docs/concepts2/auto_dispose
@riverpod
final class IntentionActionsViewModel extends _$IntentionActionsViewModel {
  late IntentionId _intentionId;
  late IntentionPageInstance _pageInstance;
  late PersonalGraphRepository _repository;
  StreamSubscription<GraphCommandCompletion>? _completions;

  /// Показан ли список; до первого [setVisible] неизвестно, и чтений нет.
  bool? _visible;

  /// Каждая смена режима или плитки отбрасывает ответы прежних чтений.
  var _generation = 0;
  GraphRevision? _requiredRevision;
  Object? _assembly;
  Object? _page;

  @override
  IntentionActionsState build(
    IntentionId intentionId,
    IntentionPageInstance pageInstance,
  ) {
    _intentionId = intentionId;
    _pageInstance = pageInstance;
    _repository = ref.watch(personalGraphRepositoryProvider);
    unawaited(_completions?.cancel());
    _completions = ref
        .watch(graphCommandCoordinatorProvider.notifier)
        .completions
        .listen((completion) {
          scheduleMicrotask(() => _onCompletion(completion));
        });
    ref.onDispose(() => unawaited(_completions?.cancel()));
    _visible = null;
    _requiredRevision = null;
    _assembly = null;
    _page = null;
    ++_generation;
    return const IntentionActionsHidden();
  }

  /// Показывает или прячет список; первый вызов начинает чтения. Показ читает
  /// выбранную плитку заново с первой порции, а сокрытие освобождает строки и
  /// продолжение.
  void setVisible(bool visible) {
    if (_visible == visible) return;
    _visible = visible;
    ++_generation;
    _page = null;
    state = visible
        ? IntentionActionsInitialLoad(
            counts: state.counts,
            role: _pageInstance.actionsRole,
          )
        : IntentionActionsHidden(counts: state.counts);
    unawaited(_assemble());
  }

  /// Отбрасывает строки прежней плитки и запоминает новую в экземпляре.
  void selectRole(IntentionActionRole role) {
    final current = state;
    if (_visible != true || current is IntentionActionsHidden) return;
    final selected = switch (current) {
      IntentionActionsLoaded(:final role) => role,
      IntentionActionsInitialLoad(:final role) ||
      IntentionActionsInitialFailure(:final role) => role,
      IntentionActionsHidden() => null,
    };
    if (selected == role) return;
    _pageInstance.actionsRole = role;
    ++_generation;
    _page = null;
    state = IntentionActionsInitialLoad(counts: current.counts, role: role);
    unawaited(_assemble());
  }

  /// Повторяет первое чтение после доказанно временного отказа.
  Future<void> retryFirstPage() {
    final current = state;
    if (current is! IntentionActionsInitialFailure || !current.canRetry) {
      return Future.value();
    }
    state = IntentionActionsInitialLoad(
      counts: current.counts,
      role: current.role,
    );
    return _assemble();
  }

  Future<void> retryRefresh() {
    final current = state;
    if (current is IntentionActionsLoaded && current.canRetryRefresh) {
      return _assemble(base: current);
    }
    return Future.value();
  }

  /// Подгружает следующую порцию, когда подвал списка подошёл к экрану.
  /// Устаревшая или занятая часть порцию не запрашивает.
  Future<void> loadMore() {
    final current = state;
    if (current is! IntentionActionsLoaded ||
        current.freshness is! IntentionActionsCurrent ||
        current.nextCursor == null ||
        current.page is! IntentionActionsPageIdle ||
        _assembly != null) {
      return Future.value();
    }
    return _loadMore(current);
  }

  Future<void> retryLoadMore() {
    final current = state;
    if (current is IntentionActionsLoaded) {
      if (current.page case IntentionActionsPageFailure(canRetry: true)) {
        return _loadMore(current);
      }
    }
    return Future.value();
  }

  /// Сборка читает числа и, пока список показан, строки. [base] — прежняя
  /// подтверждённая часть: она остаётся на экране, а замена покрывает
  /// столько же строк, и [extra] строк сверху.
  Future<void> _assemble({IntentionActionsLoaded? base, int extra = 0}) async {
    final request = Object();
    _assembly = request;
    final generation = _generation;
    final visible = _visible ?? false;
    if (base != null) {
      state = base.copyWith(
        page: const IntentionActionsPageIdle(),
        freshness: const IntentionActionsRefreshing(),
      );
    }
    final result = await assembleIntentionActions(
      intentionId: _intentionId,
      role: _pageInstance.actionsRole,
      itemCount: visible ? (base?.items.length ?? 0) + extra : 0,
      pageSize: visible
          ? IntentionActionsQuery.defaultPageSize
          : IntentionActionsQuery.minPageSize,
      readPage: _repository.getIntentionActionsPage,
      isCurrent: () =>
          ref.mounted &&
          generation == _generation &&
          identical(_assembly, request),
      acceptsRevision: (revision) => !_precedesRequired(revision),
    );
    if (!ref.mounted ||
        generation != _generation ||
        !identical(_assembly, request)) {
      return;
    }
    _assembly = null;
    switch (result) {
      case IntentionActionsAssembled(:final counts) when !visible:
        state = IntentionActionsHidden(counts: counts);
        // Подтверждение пришло, пока ответ шёл: нужна ревизия не старше его.
        if (_precedesRequired(result.revision)) unawaited(_assemble());
      case IntentionActionsAssembled():
        _pageInstance.actionsRole = result.role;
        final loaded = IntentionActionsLoaded(
          role: result.role,
          counts: result.counts,
          revision: result.revision,
          items: result.items,
          nextCursor: result.nextCursor,
        );
        state = loaded;
        if (_precedesRequired(result.revision)) {
          unawaited(_assemble(base: loaded));
        }
      case IntentionActionsAssemblyFailed():
        // Числа без вкладки не показывают отказа: вкладка читает их заново
        // при показе и тогда называет причину.
        if (!visible) return;
        state = base == null
            ? IntentionActionsInitialFailure(
                failure: result.failure,
                counts: state.counts,
                role: _pageInstance.actionsRole,
              )
            : base.copyWith(freshness: IntentionActionsStale(result.failure));
      case IntentionActionsAssemblyCancelled():
        break;
    }
  }

  Future<void> _loadMore(IntentionActionsLoaded base) async {
    final request = Object();
    final generation = _generation;
    _page = request;
    state = base.copyWith(page: const IntentionActionsPageLoading());
    IntentionActionsPageResult result;
    try {
      result = await _repository.getIntentionActionsPage(
        IntentionActionsQuery(
          intentionId: _intentionId,
          role: base.role,
          cursor: base.nextCursor,
        ),
      );
    } on Object {
      result = const IntentionActionsPageError(
        IntentionActionsUnexpectedFailure(),
      );
    }
    if (!ref.mounted ||
        generation != _generation ||
        !identical(_page, request)) {
      return;
    }
    _page = null;
    final current = state;
    if (current is! IntentionActionsLoaded) return;
    switch (result) {
      case GraphResultSuccess(
        value: final IntentionActionsContinuationPage page,
      ):
        if (page.revision.compareTo(current.revision) !=
                GraphRevisionOrder.same ||
            _precedesRequired(page.revision)) {
          await _assemble(
            base: current,
            extra: IntentionActionsQuery.defaultPageSize,
          );
        } else {
          state = current.appended(page);
        }
      case GraphResultFailure(failure: IntentionActionsSnapshotExpired()):
        await _assemble(
          base: current,
          extra: IntentionActionsQuery.defaultPageSize,
        );
      case GraphResultFailure(:final failure):
        state = current.copyWith(page: IntentionActionsPageFailure(failure));
      case GraphResultSuccess():
        state = current.copyWith(
          page: const IntentionActionsPageFailure(
            IntentionActionsUnexpectedFailure(),
          ),
        );
    }
  }

  void _onCompletion(GraphCommandCompletion completion) {
    if (!ref.mounted) return;
    final package = completion.confirmedChange;
    if (package == null) return;
    final current = state;
    for (final known in [
      if (current is IntentionActionsLoaded) current.revision,
      ?_requiredRevision,
    ]) {
      final order = package.revision.compareTo(known);
      if (order == GraphRevisionOrder.older ||
          order == GraphRevisionOrder.same) {
        return;
      }
    }
    // Идущая сборка и подгрузка с более старой ревизией отбрасываются сами.
    _requiredRevision = package.revision;
    if (!_affects(package.changes, current) || _assembly != null) return;
    switch (current) {
      case IntentionActionsLoaded():
        unawaited(_assemble(base: current));
      case IntentionActionsHidden():
        unawaited(_assemble());
      case IntentionActionsInitialLoad() || IntentionActionsInitialFailure():
        break;
    }
  }

  /// Числа зависят от действий с намерением в пути, а строки — ещё и от
  /// корневых намерений загруженных строк.
  bool _affects(List<GraphChange> changes, IntentionActionsState current) {
    final roots = switch (current) {
      IntentionActionsLoaded(:final items) => {
        for (final item in items) item.rootIntentionId,
      },
      _ => const <IntentionId>{},
    };
    bool involves(Action? action) =>
        action != null && action.path.intentions.contains(_intentionId);
    for (final change in changes) {
      switch (change) {
        case ActionChange(:final before, :final after):
          if (involves(before) || involves(after)) return true;
        case IntentionCatalogMutation(:final before, :final after):
          if (roots.contains(before?.summary.id) ||
              roots.contains(after?.summary.id)) {
            return true;
          }
        case GraphChange():
          break;
      }
    }
    return false;
  }

  bool _precedesRequired(GraphRevision revision) {
    final required = _requiredRevision;
    if (required == null) return false;
    final order = revision.compareTo(required);
    return order == GraphRevisionOrder.older ||
        order == GraphRevisionOrder.differentEpoch;
  }
}
