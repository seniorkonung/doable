import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../graph/application/graph_command_coordinator.dart';
import '../../../graph/application/graph_revision.dart';
import '../../../intention/application/intention_catalog.dart';
import '../../../intention/domain/intention.dart';
import '../../../intention/domain/intention_id.dart';
import '../../../intention/presentation/catalog/intention_catalog_purpose.dart';
import 'relation_batch_state.dart';

part 'relation_batch_view_model.g.dart';

final relationBatchChangesProvider =
    Provider<Stream<ConfirmedGraphChangePackage>>(
      (ref) => ref
          .watch(graphCommandCoordinatorProvider.notifier)
          .completions
          .map((completion) => completion.confirmedChange)
          .where((package) => package != null)
          .cast<ConfirmedGraphChangePackage>(),
    );

/// Отметки принадлежат экземпляру поиска и не зависят от его выдачи.
@riverpod
final class RelationBatchViewModel extends _$RelationBatchViewModel {
  late IntentionId _pageId;
  final _selected = <IntentionId, String>{};
  late String _pageTitle;

  @override
  RelationBatchState build(
    IntentionSearchSession session,
    IntentionId pageId,
    String pageTitle,
  ) {
    _pageId = pageId;
    _pageTitle = pageTitle;
    final subscription = ref
        .watch(relationBatchChangesProvider)
        .listen(_onPackage);
    ref.onDispose(() => unawaited(subscription.cancel()));
    return _snapshot();
  }

  void toggle(IntentionId id, String title) {
    if (_selected.containsKey(id)) {
      _selected.remove(id);
    } else {
      _selected[id] = title;
    }
    state = _snapshot();
  }

  void _onPackage(ConfirmedGraphChangePackage package) {
    if (!ref.mounted) return;
    var changed = false;
    for (final change in package.changes) {
      switch (change) {
        case IntentionCatalogUpdated(:final before, :final after):
          final previous = before.summary;
          final current = after.summary;
          if (current.id == _pageId && previous.title != current.title) {
            _pageTitle = current.title;
            changed = true;
          }
          if (_selected.containsKey(current.id)) {
            if (current.archiveState == IntentionArchiveState.archived) {
              _selected.remove(current.id);
              changed = true;
            } else if (previous.title != current.title &&
                _selected[current.id] != current.title) {
              _selected[current.id] = current.title;
              changed = true;
            }
          }
        case IntentionCatalogDeleted(:final entry):
          changed = _selected.remove(entry.summary.id) != null || changed;
        case GraphChange():
          break;
      }
    }
    if (changed) state = _snapshot();
  }

  RelationBatchState _snapshot() => RelationBatchState(
    pageTitle: _pageTitle,
    selected: [
      for (final entry in _selected.entries)
        RelationBatchSelection(id: entry.key, title: entry.value),
    ],
  );
}
