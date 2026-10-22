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
    final result = await _readCatalog();
    if (!ref.mounted || generation != _generation) return;
    // Отказ чтения, за которым уже запрошено следующее, ничего не решает.
    if (result is GraphResultFailure && _refreshNeeded) return;
    switch (result) {
      case GraphResultSuccess(
        value: TagSelectionSnapshot(:final rows, :final revision),
      ):
        if (_precedesRequired(revision) || _precedesShown(revision)) {
          if (++_staleReadAttempts >= _maxStaleReads) {
            _refreshNeeded = false;
            _readFailed(const TagCatalogUnavailableFailure());
          } else {
            _refreshNeeded = true;
          }
          return;
        }
        _refreshNeeded = false;
        _staleReadAttempts = 0;
        _shownRevision = revision;
        state = state.withCatalog(
          TagsPanelLoaded([
            for (final row in rows)
              TagsPanelRow(tag: row.tag, isMarked: row.isAssigned),
          ]),
        );
      case GraphResultSuccess(value: TagBrowseSnapshot()):
        _readFailed(const TagCatalogUnexpectedFailure());
      case GraphResultFailure(failure: TagCatalogIntentionNotFound()):
        _generation++;
        _refreshNeeded = false;
        state = state.withCatalog(const TagsPanelIntentionMissing());
      case GraphResultFailure(:final failure):
        _readFailed(failure);
    }
  }

  Future<TagCatalogResult> _readCatalog() async {
    final mode = switch (_context) {
      TagsPanelAssignmentContext(:final intentionId) => TagCatalogSelectionMode(
        intentionId,
      ),
    };
    try {
      return await _repository.getTagCatalog(mode);
    } on Object {
      return const TagCatalogError(TagCatalogUnexpectedFailure());
    }
  }

  void _readFailed(TagCatalogReadFailure failure) {
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
          catalog.withRows(_applied(catalog.rows, package)),
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
      rows
        ..sort((a, b) => a.tag.position.value.compareTo(b.tag.position.value));

  bool _precedesRequired(GraphRevision revision) {
    final required = _requiredRevision;
    if (required == null) return false;
    final order = revision.compareTo(required);
    return order == GraphRevisionOrder.older ||
        order == GraphRevisionOrder.differentEpoch;
  }

  bool _precedesShown(GraphRevision revision) =>
      _shownRevision?.compareTo(revision) == GraphRevisionOrder.newer;
}
