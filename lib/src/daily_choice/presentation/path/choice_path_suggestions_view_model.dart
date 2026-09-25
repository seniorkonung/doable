import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../graph/application/graph_change.dart';
import '../../../graph/application/graph_command_coordinator.dart';
import '../../../graph/application/graph_command_result.dart';
import '../../../graph/application/graph_revision.dart';
import '../../../graph/application/personal_graph_repository.dart';
import '../../../intention/application/intention_catalog.dart';
import '../../../intention/application/intention_details.dart';
import '../../../intention/application/intention_result.dart'
    as intention_result;
import '../../../intention/domain/intention_id.dart';
import '../../../long_term_relation/domain/long_term_relation_id.dart';
import '../../application/choice_path_suggestions.dart';
import '../../application/daily_choice_details.dart';
import '../../domain/daily_choice.dart';
import '../../domain/daily_choice_id.dart';
import 'choice_path_suggestions_state.dart';

/// Хранит только текущую ограниченную выдачу и одно актуальное чтение.
/// Поток изменений передаётся из общего координатора графа.
final class ChoicePathSuggestionsViewModel extends ChangeNotifier {
  factory ChoicePathSuggestionsViewModel.fromCoordinator(
    PersonalGraphRepository repository,
    GraphCommandCoordinator coordinator,
    ChoicePathSuggestionsQuery query,
  ) => ChoicePathSuggestionsViewModel(
    repository,
    coordinator.completions
        .where((completion) => completion.confirmedChange != null)
        .map((completion) => completion.confirmedChange!),
    query,
  );

  ChoicePathSuggestionsViewModel(
    this._repository,
    Stream<ConfirmedGraphChangePackage> changes,
    ChoicePathSuggestionsQuery query,
  ) : _query = query,
      _state = ChoicePathSuggestionsLoading(query) {
    _changesSubscription = changes.listen(
      _onChange,
      onError: (Object _, StackTrace _) =>
          _fail(const ChoicePathSuggestionsUnexpectedFailure()),
    );
    _startRead();
    _observeParticipant();
  }

  final PersonalGraphRepository _repository;
  late final StreamSubscription<ConfirmedGraphChangePackage>
  _changesSubscription;
  StreamSubscription<intention_result.Result<GraphSnapshot<IntentionDetails?>>>?
  _participantSubscription;
  final Map<DailyChoiceId, StreamSubscription<DailyChoiceReadResult>>
  _candidateSubscriptions = {};
  ChoicePathSuggestionsQuery _query;
  ChoicePathSuggestionsState _state;
  GraphRevision? _requiredRevision;
  int _generation = 0;
  Object? _activeReadSelection;
  bool _readQueued = false;
  Object _selection = Object();
  Object _candidateWatch = Object();
  bool _disposed = false;

  ChoicePathSuggestionsState get state => _state;

  /// Смена участника или направления завершает прежнюю экранную сессию.
  void select(ChoicePathSuggestionsQuery query) {
    if (_disposed || _sameQuery(_query, query)) return;
    _selection = Object();
    _query = query;
    _requiredRevision = null;
    _readQueued = false;
    _cancelWatches();
    _setState(ChoicePathSuggestionsLoading(query));
    _startRead();
    _observeParticipant();
  }

  /// Явная актуализация доступна из уже полученной выдачи.
  void refresh() {
    if (_disposed || _state is! ChoicePathSuggestionsCurrent) return;
    _startRead();
  }

  /// Обычный повтор возможен только после доказанной временной недоступности.
  void retry() {
    if (_disposed) return;
    final canRetry = switch (_state) {
      ChoicePathSuggestionsLoadFailure(:final canRetry) => canRetry,
      ChoicePathSuggestionsRefreshFailure(:final canRetry) => canRetry,
      _ => false,
    };
    if (canRetry) _startRead();
  }

  AvailableChoicePathSuggestion? confirmable(DailyChoiceId id) =>
      switch (_state) {
        ChoicePathSuggestionsReady ready => ready.confirmable(id),
        _ => null,
      };

  void _startRead() {
    final generation = ++_generation;
    final snapshot = _visibleSnapshot;
    _setState(
      snapshot == null
          ? ChoicePathSuggestionsLoading(_query)
          : ChoicePathSuggestionsUpdating(snapshot),
    );
    if (identical(_activeReadSelection, _selection)) {
      _readQueued = true;
      return;
    }
    _launchRead(generation, _selection, _query);
  }

  void _launchRead(
    int generation,
    Object selection,
    ChoicePathSuggestionsQuery query,
  ) {
    _activeReadSelection = selection;
    unawaited(
      _read(generation, selection, query).whenComplete(() {
        if (_disposed || !identical(_activeReadSelection, selection)) return;
        _activeReadSelection = null;
        if (_readQueued) {
          _readQueued = false;
          _launchRead(_generation, _selection, _query);
        }
      }),
    );
  }

  Future<void> _read(
    int generation,
    Object selection,
    ChoicePathSuggestionsQuery query,
  ) async {
    for (var attempt = 0; attempt < 3; attempt++) {
      ChoicePathSuggestionsResult result;
      try {
        result = await _repository.getChoicePathSuggestions(query);
      } on Object {
        result = const ChoicePathSuggestionsError(
          ChoicePathSuggestionsUnexpectedFailure(),
        );
      }
      if (!_isCurrent(generation, selection)) return;
      switch (result) {
        case GraphResultSuccess(:final value):
          if (!_sameQuery(value.query, query)) {
            _fail(const ChoicePathSuggestionsUnexpectedFailure());
            return;
          }
          final required = _requiredRevision;
          if (required != null) {
            final order = value.revision.compareTo(required);
            if (order == GraphRevisionOrder.older ||
                order == GraphRevisionOrder.differentEpoch) {
              continue;
            }
          }
          _requiredRevision = value.revision;
          _setState(
            value.items.isEmpty
                ? ChoicePathSuggestionsEmpty(value)
                : ChoicePathSuggestionsReady(value),
          );
          _observeCandidates(value);
          return;
        case GraphResultFailure(:final failure):
          if (failure is ChoicePathSuggestionsIntentionNotFoundFailure) {
            _cancelCandidateWatches();
            _setState(ChoicePathSuggestionsNotFound(query));
          } else {
            _fail(failure);
          }
          return;
      }
    }
    _fail(const ChoicePathSuggestionsUnavailableFailure());
  }

  void _observeParticipant() {
    final selection = _selection;
    try {
      _participantSubscription = _repository
          .watchIntention(_query.participantId)
          .listen(
            (result) {
              if (_disposed || !identical(selection, _selection)) return;
              switch (result) {
                case GraphResultSuccess(:final value):
                  if (value.value == null) {
                    ++_generation;
                    _cancelCandidateWatches();
                    _setState(ChoicePathSuggestionsNotFound(_query));
                  } else {
                    _observeRevision(value.revision);
                  }
                case GraphResultFailure(:final failure):
                  _fail(switch (failure) {
                    intention_result.IntentionUnavailableFailure() =>
                      const ChoicePathSuggestionsUnavailableFailure(),
                    intention_result.IntentionCorruptionFailure() =>
                      const ChoicePathSuggestionsCorruptionFailure(),
                    _ => const ChoicePathSuggestionsUnexpectedFailure(),
                  });
              }
            },
            onError: (Object _, StackTrace _) {
              if (identical(selection, _selection)) {
                _fail(const ChoicePathSuggestionsUnexpectedFailure());
              }
            },
          );
    } on Object {
      _fail(const ChoicePathSuggestionsUnexpectedFailure());
    }
  }

  void _observeCandidates(ChoicePathSuggestionsSnapshot snapshot) {
    _cancelCandidateWatches();
    final watch = _candidateWatch;
    for (final candidate in snapshot.items) {
      try {
        _candidateSubscriptions[candidate.originChoiceId] = _repository
            .watchDailyChoice(candidate.originChoiceId)
            .listen(
              (result) {
                if (_disposed || !identical(watch, _candidateWatch)) return;
                switch (result) {
                  case GraphResultSuccess(:final value):
                    if (value.value == null) {
                      _startRead();
                    } else {
                      _observeRevision(value.revision);
                    }
                  case GraphResultFailure(:final failure):
                    _fail(switch (failure) {
                      DailyChoiceReadUnavailableFailure() =>
                        const ChoicePathSuggestionsUnavailableFailure(),
                      DailyChoiceReadCorruptionFailure() =>
                        const ChoicePathSuggestionsCorruptionFailure(),
                      DailyChoiceReadUnexpectedFailure() =>
                        const ChoicePathSuggestionsUnexpectedFailure(),
                    });
                }
              },
              onError: (Object _, StackTrace _) {
                if (identical(watch, _candidateWatch)) {
                  _fail(const ChoicePathSuggestionsUnexpectedFailure());
                }
              },
            );
      } on Object {
        _fail(const ChoicePathSuggestionsUnexpectedFailure());
        return;
      }
    }
  }

  void _onChange(ConfirmedGraphChangePackage package) {
    if (_disposed) return;
    final known = _requiredRevision;
    if (known != null) {
      final order = package.revision.compareTo(known);
      if (order == GraphRevisionOrder.older ||
          order == GraphRevisionOrder.same) {
        return;
      }
    }
    if (_affectsCurrent(package.changes) ||
        (known != null &&
            package.revision.compareTo(known) ==
                GraphRevisionOrder.differentEpoch)) {
      _requiredRevision = package.revision;
      _startRead();
    }
  }

  bool _affectsCurrent(List<GraphChange> changes) {
    final snapshot = _visibleSnapshot;
    if (snapshot == null) return true;
    final choiceIds = {for (final item in snapshot.items) item.originChoiceId};
    final intentionIds = <IntentionId>{
      _query.participantId,
      ...snapshot.observedIntentionIds,
    };
    final relationIds = <LongTermRelationId>{...snapshot.observedRelationIds};
    for (final item in snapshot.items) {
      intentionIds.add(item.source.id);
      intentionIds.add(item.action.id);
      for (final step in item.path) {
        intentionIds.add(step.source.id);
        intentionIds.add(step.related.id);
        relationIds.add(step.relation.id);
      }
    }
    for (final change in changes) {
      switch (change) {
        case DailyChoiceChange(:final before, :final after):
          if (choiceIds.contains(before?.id) ||
              choiceIds.contains(after?.id) ||
              _matchesParticipant(before) ||
              _matchesParticipant(after)) {
            return true;
          }
        case IntentionCatalogMutation(:final before, :final after):
          if (intentionIds.contains(before?.summary.id) ||
              intentionIds.contains(after?.summary.id)) {
            return true;
          }
        case LongTermRelationChange(:final id):
          if (relationIds.contains(id)) return true;
        case GraphChange():
          break;
      }
    }
    return false;
  }

  bool _matchesParticipant(DailyChoice? choice) =>
      choice != null &&
      switch (_query) {
        ChoicePathSuggestionsForSource() =>
          choice.sourceIntentionId == _query.participantId,
        ChoicePathSuggestionsForAction() =>
          choice.selectedIntentionId == _query.participantId,
      };

  void _observeRevision(GraphRevision revision) {
    if (_disposed) return;
    final known = _requiredRevision;
    if (known == null) {
      _requiredRevision = revision;
      return;
    }
    final order = revision.compareTo(known);
    if (order == GraphRevisionOrder.newer ||
        order == GraphRevisionOrder.differentEpoch) {
      _requiredRevision = revision;
      _startRead();
    }
  }

  void _fail(ChoicePathSuggestionsFailure failure) {
    if (_disposed) return;
    ++_generation;
    final snapshot = _visibleSnapshot;
    _setState(
      snapshot == null
          ? ChoicePathSuggestionsLoadFailure(_query, failure)
          : ChoicePathSuggestionsRefreshFailure(snapshot, failure),
    );
  }

  ChoicePathSuggestionsSnapshot? get _visibleSnapshot => switch (_state) {
    ChoicePathSuggestionsCurrent(:final snapshot) => snapshot,
    ChoicePathSuggestionsUpdating(:final snapshot) => snapshot,
    ChoicePathSuggestionsRefreshFailure(:final snapshot) => snapshot,
    _ => null,
  };

  bool _isCurrent(int generation, Object selection) =>
      !_disposed &&
      generation == _generation &&
      identical(selection, _selection);

  bool _sameQuery(
    ChoicePathSuggestionsQuery left,
    ChoicePathSuggestionsQuery right,
  ) =>
      left.runtimeType == right.runtimeType &&
      left.participantId == right.participantId;

  void _setState(ChoicePathSuggestionsState value) {
    if (_disposed) return;
    _state = value;
    notifyListeners();
  }

  void _cancelCandidateWatches() {
    _candidateWatch = Object();
    for (final subscription in _candidateSubscriptions.values) {
      unawaited(subscription.cancel());
    }
    _candidateSubscriptions.clear();
  }

  void _cancelWatches() {
    unawaited(_participantSubscription?.cancel());
    _participantSubscription = null;
    _cancelCandidateWatches();
  }

  @override
  void dispose() {
    _disposed = true;
    _readQueued = false;
    ++_generation;
    _selection = Object();
    _cancelWatches();
    unawaited(_changesSubscription.cancel());
    super.dispose();
  }
}
