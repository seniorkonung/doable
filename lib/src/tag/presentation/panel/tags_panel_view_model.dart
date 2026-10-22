import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../graph/application/graph_command_coordinator.dart';
import '../../../graph/application/graph_command_result.dart';
import '../../../graph/application/graph_revision.dart';
import '../../../graph/application/personal_graph_repository.dart';
import '../../../graph/application/personal_graph_repository_provider.dart';
import '../../../intention/application/intention_catalog.dart';
import '../../application/tag_catalog.dart';
import '../../application/tag_change.dart';
import '../../application/tag_command.dart';
import '../../application/tag_result.dart';
import '../../domain/tag_id.dart';
import '../catalog/tag_catalog_filter.dart';
import 'tags_panel_context.dart';
import 'tags_panel_state.dart';

part 'tags_panel_view_model.g.dart';

/// Узкая зависимость позволяет проверять согласование без команд записи.
final tagsPanelChangesProvider = Provider<Stream<ConfirmedGraphChangePackage>>(
  (ref) => ref
      .watch(graphCommandCoordinatorProvider.notifier)
      .completions
      .map((completion) => completion.confirmedChange)
      .where((package) => package != null)
      .cast<ConfirmedGraphChangePackage>(),
);

@riverpod
final class TagsPanelViewModel extends _$TagsPanelViewModel {
  static const _maxStaleReads = 8;

  late TagsPanelContext _context;
  late PersonalGraphRepository _repository;
  StreamSubscription<ConfirmedGraphChangePackage>? _changes;
  GraphRevision? _shownRevision;
  GraphRevision? _requiredRevision;
  Future<void>? _activeRead;
  bool _refreshNeeded = false;
  int _generation = 0;
  int _staleReadAttempts = 0;

  @override
  TagsPanelState build(TagsPanelOpening opening) {
    _context = opening.context;
    _repository = ref.watch(personalGraphRepositoryProvider);
    _shownRevision = null;
    _requiredRevision = null;
    _activeRead = null;
    _refreshNeeded = false;
    _generation++;
    _staleReadAttempts = 0;
    _changes = ref.watch(tagsPanelChangesProvider).listen(_onChange);
    ref.onDispose(() => unawaited(_changes?.cancel()));
    _requestRead();
    return const TagsPanelState(catalog: TagsPanelLoading());
  }

  /// Корректный ввод сразу становится фильтром. Некорректный сохраняет
  /// последний корректный фильтр и отмечается ошибкой ввода.
  void search(String input) {
    state = state.withSearch(switch (TagCatalogFilter.fromInput(input)) {
      final TagCatalogFilter filter => TagsPanelSearch(
        filter: filter,
        inputIsInvalid: false,
      ),
      TagCatalogFilterInvalidUnicode() => TagsPanelSearch(
        filter: state.search.filter,
        inputIsInvalid: true,
      ),
    });
  }

  /// Нажатие на строку назначает неотмеченный тег намерению или снимает
  /// отмеченный. Отметка меняется только по подтверждённому пакету, поэтому
  /// отказ записи оставляет её прежней, а сам отказ принадлежит общей
  /// поверхности. Пока назначения этого намерения меняются, координатор
  /// отклоняет нажатие по занятому ключу намерения без очереди. На
  /// неактуальных строках и без намерения нажатие недоступно: `null`.
  TagCommandStart? toggle(TagId tagId) {
    final catalog = state.catalog;
    if (catalog is! TagsPanelLoaded || !catalog.rowsAreCurrent) return null;
    final row = catalog.rows.where((row) => row.tag.id == tagId).firstOrNull;
    if (row == null) return null;
    final coordinator = ref.read(graphCommandCoordinatorProvider.notifier);
    return switch (_context) {
      TagsPanelAssignmentContext(:final intentionId) when row.isMarked =>
        coordinator.acceptTagRemoveAssignment(
          RemoveTagAssignment(tagId: tagId, intentionId: intentionId),
        ),
      TagsPanelAssignmentContext(:final intentionId) =>
        coordinator.acceptTagAssign(
          AssignTag(tagId: tagId, intentionId: intentionId),
        ),
    };
  }

  /// Удаляет тег [tagId] со всеми назначениями после подтверждения
  /// пользователя. Команда относится к идентификатору, поэтому удаляет и
  /// назначения, сохранённые после показа строк. Подтверждённый пакет убирает
  /// строку, а отказ записи принадлежит общей поверхности.
  TagCommandStart delete(TagId tagId) => ref
      .read(graphCommandCoordinatorProvider.notifier)
      .acceptTagDelete(DeleteTag(tagId));

  /// Ставит тег [tagId] на место [index] показанного списка и сразу
  /// показывает новый порядок. Место отправляется соседом: после тега, который
  /// окажется перед ним, либо первым. Подтверждённый пакет перестановки
  /// применяется к строкам без чтения, а отказ записи возвращает
  /// подтверждённый порядок и принадлежит общей поверхности. Непринятая
  /// координатором команда порядок не меняет. Пока поиск сужает список,
  /// строки неактуальны или выполняется предыдущая перестановка, а также при
  /// перестановке на текущее место команда не отправляется: `null`.
  TagCommandStart? move(TagId tagId, int index) {
    final catalog = state.catalog;
    if (!state.canReorder || catalog is! TagsPanelLoaded) return null;
    final rows = catalog.rows;
    final from = rows.indexWhere((row) => row.tag.id == tagId);
    if (from == -1 || index < 0 || index >= rows.length || index == from) {
      return null;
    }
    final others = [
      for (final row in rows)
        if (row.tag.id != tagId) row,
    ];
    final command = MoveTag(
      tagId: tagId,
      placement: index == 0
          ? TagPlacement.first
          : AfterTagPlacement(others[index - 1].tag.id),
    );
    final start = ref
        .read(graphCommandCoordinatorProvider.notifier)
        .acceptTagMove(command);
    if (start case TagCommandAccepted(:final future)) {
      state = state.withCatalog(catalog.withPendingMove(command));
      unawaited(_settleMove(future, _generation));
    }
    return start;
  }

  /// Подтверждённый пакет применяется до снятия показанной перестановки, чтобы
  /// подтверждённый порядок не мелькнул прежним, даже если пакет ещё не
  /// пришёл из потока изменений.
  Future<void> _settleMove(
    Future<TagCommandCompletion> move,
    int generation,
  ) async {
    final completion = await move;
    if (!ref.mounted || generation != _generation) return;
    if (completion case TagCommandSucceededCompletion(:final confirmedChange)) {
      _onChange(confirmedChange);
    }
    if (state.catalog case final TagsPanelLoaded loaded) {
      state = state.withCatalog(loaded.withPendingMove(null));
    }
  }

  /// Принятое из листа создание принадлежит этому открытию панели, а не
  /// экранной сессии листа, поэтому закрытие листа его не прерывает. После
  /// подтверждения модель один раз очищает поиск и отмечает тег отдельной
  /// командой назначения; её отклонение или отказ оставляют тег
  /// неотмеченным. Открытие, закрытое до подтверждения, тег не отмечает,
  /// даже если модель ещё жива.
  void acceptCreation(TagCommandAccepted creation) =>
      unawaited(_markCreated(creation.future));

  Future<void> _markCreated(Future<TagCommandCompletion> creation) async {
    final completion = await creation;
    if (!ref.mounted || opening.isClosed) return;
    if (completion.result case GraphResultSuccess(
      value: TagCreated(:final tag),
    )) {
      state = state.withSearch(TagsPanelSearch.initial);
      final coordinator = ref.read(graphCommandCoordinatorProvider.notifier);
      switch (_context) {
        case TagsPanelAssignmentContext(:final intentionId):
          coordinator.acceptTagAssign(
            AssignTag(tagId: tag.id, intentionId: intentionId),
          );
      }
    }
  }

  void retryLoad() {
    if (state.catalog case TagsPanelLoadFailure(canRetry: true)) {
      state = state.withCatalog(const TagsPanelLoading());
      _staleReadAttempts = 0;
      _requestRead();
    }
  }

  /// Строки остаются неактуальными, пока повтор не завершится успехом.
  void retryRefresh() {
    if (state.catalog case TagsPanelLoaded(canRetryRefresh: true)) {
      _staleReadAttempts = 0;
      _requestRead();
    }
  }

  /// Одновременно выполняется одно чтение; запрос во время него выполняется
  /// после его завершения.
  void _requestRead() {
    if (_activeRead != null) {
      _refreshNeeded = true;
      return;
    }
    final read = _load(_generation);
    _activeRead = read;
    unawaited(
      read.whenComplete(() {
        if (!identical(_activeRead, read)) return;
        _activeRead = null;
        if (_refreshNeeded && ref.mounted) {
          _refreshNeeded = false;
          _requestRead();
        }
      }),
    );
  }

  Future<void> _load(int generation) async {
    final result = await _repository.getTagCatalog(switch (_context) {
      TagsPanelAssignmentContext(:final intentionId) => TagCatalogSelectionMode(
        intentionId,
      ),
    });
    if (!ref.mounted || generation != _generation) return;
    // Отказ чтения, за которым уже запрошено следующее, ничего не решает.
    if (result is GraphResultFailure && _refreshNeeded) return;
    switch (result) {
      case GraphResultSuccess(
        value: TagSelectionSnapshot(:final rows, :final revision),
      ):
        if (_precedesRequired(revision)) {
          if (++_staleReadAttempts >= _maxStaleReads) {
            _refreshNeeded = false;
            _readFailed(TagsPanelReadFailure.unavailable);
          } else {
            _refreshNeeded = true;
          }
          return;
        }
        _refreshNeeded = false;
        _staleReadAttempts = 0;
        _shownRevision = revision;
        state = state.withCatalog(
          TagsPanelLoaded(
            [
              for (final row in rows)
                TagsPanelRow(tag: row.tag, isMarked: row.isAssigned),
            ],
            pendingMove: switch (state.catalog) {
              TagsPanelLoaded(:final pendingMove) => pendingMove,
              _ => null,
            },
          ),
        );
      case GraphResultSuccess(value: TagBrowseSnapshot()):
        _readFailed(TagsPanelReadFailure.unexpected);
      case GraphResultFailure(failure: TagCatalogIntentionNotFound()):
        _generation++;
        _refreshNeeded = false;
        state = state.withCatalog(const TagsPanelIntentionMissing());
      case GraphResultFailure(failure: TagCatalogUnavailableFailure()):
        _readFailed(TagsPanelReadFailure.unavailable);
      case GraphResultFailure(failure: TagCatalogCorruptionFailure()):
        _readFailed(TagsPanelReadFailure.corruption);
      case GraphResultFailure(failure: TagCatalogUnexpectedFailure()):
        _readFailed(TagsPanelReadFailure.unexpected);
    }
  }

  void _readFailed(TagsPanelReadFailure failure) {
    state = state.withCatalog(switch (state.catalog) {
      final TagsPanelLoaded loaded => loaded.withRefreshFailure(failure),
      _ => TagsPanelLoadFailure(failure),
    });
  }

  /// Пакет, который модель полностью объясняет, применяется к строкам без
  /// чтения; остальные запускают фоновое перечитывание. Чтение, начатое до
  /// пакета, не возвращает строки к состоянию до него.
  void _onChange(ConfirmedGraphChangePackage package) {
    final required = _requiredRevision;
    if (required != null) {
      final order = package.revision.compareTo(required);
      if (order == GraphRevisionOrder.older ||
          order == GraphRevisionOrder.same) {
        return;
      }
    }
    _requiredRevision = package.revision;
    _staleReadAttempts = 0;
    final catalog = state.catalog;
    if (catalog is! TagsPanelLoaded) return;
    final shown = _shownRevision!;
    switch (package.revision.compareTo(shown)) {
      case GraphRevisionOrder.older || GraphRevisionOrder.same:
        return;
      case GraphRevisionOrder.newer when _explains(package):
        _shownRevision = package.revision;
        state = state.withCatalog(
          catalog.withConfirmedRows(_applied(catalog.confirmedRows, package)),
        );
      case GraphRevisionOrder.newer || GraphRevisionOrder.differentEpoch:
        _requestRead();
    }
  }

  /// Изменения тегов и назначений вместе с кратким снимком намерения, который
  /// отражает назначение того же пакета.
  bool _explains(ConfirmedGraphChangePackage package) {
    final assignedIntentions = {
      for (final change in package.changes)
        if (change case TagAssignmentChangedChange(:final assignment))
          assignment.intentionId,
    };
    return package.changes.every(
      (change) => switch (change) {
        TagChange() => true,
        IntentionCatalogUpdated(:final after) => assignedIntentions.contains(
          after.summary.id,
        ),
        _ => false,
      },
    );
  }

  List<TagsPanelRow> _applied(
    List<TagsPanelRow> rows,
    ConfirmedGraphChangePackage package,
  ) {
    final intentionId = switch (_context) {
      TagsPanelAssignmentContext(:final intentionId) => intentionId,
    };
    var applied = rows;
    for (final change in package.changes) {
      applied = switch (change) {
        TagCreatedChange(:final after) => _inManualOrder([
          TagsPanelRow(tag: after, isMarked: false),
          ...applied,
        ]),
        TagUpdatedChange(:final after) => _inManualOrder([
          for (final row in applied)
            if (row.tag.id == after.id)
              TagsPanelRow(tag: after, isMarked: row.isMarked)
            else
              row,
        ]),
        TagDeletedChange(:final tagId) => [
          for (final row in applied)
            if (row.tag.id != tagId) row,
        ],
        TagAssignmentChangedChange(:final assignment, :final state)
            when assignment.intentionId == intentionId =>
          [
            for (final row in applied)
              if (row.tag.id == assignment.tagId)
                TagsPanelRow(
                  tag: row.tag,
                  isMarked: state == TagAssignmentState.assigned,
                )
              else
                row,
          ],
        _ => applied,
      };
    }
    return applied;
  }

  // Места уникальны, поэтому нестабильная сортировка однозначна.
  static List<TagsPanelRow> _inManualOrder(List<TagsPanelRow> rows) =>
      rows..sort((a, b) => a.tag.position.compareTo(b.tag.position));

  bool _precedesRequired(GraphRevision revision) {
    final required = _requiredRevision;
    if (required == null) return false;
    final order = revision.compareTo(required);
    return order == GraphRevisionOrder.older ||
        order == GraphRevisionOrder.differentEpoch;
  }
}
