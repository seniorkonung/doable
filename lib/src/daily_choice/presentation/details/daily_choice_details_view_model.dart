import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../graph/application/graph_command_result.dart';
import '../../../graph/application/graph_revision.dart';
import '../../../graph/application/personal_graph_repository.dart';
import '../../application/daily_choice_details.dart';
import '../../domain/daily_choice_id.dart';
import 'daily_choice_details_state.dart';

/// Живой целый снимок одного выбора; экран владеет подпиской.
final class DailyChoiceDetailsViewModel extends ChangeNotifier {
  DailyChoiceDetailsViewModel(this._repository, this._id) {
    _observe();
  }

  final PersonalGraphRepository _repository;
  final DailyChoiceId _id;
  StreamSubscription<DailyChoiceReadResult>? _subscription;
  GraphRevision? _acceptedRevision;
  int _generation = 0;
  DailyChoiceDetailsState _state = const DailyChoiceDetailsLoading();

  DailyChoiceDetailsState get state => _state;

  void retry() {
    if (_state is! DailyChoiceDetailsUnavailable) return;
    _setState(const DailyChoiceDetailsLoading());
    _observe();
  }

  void _observe() {
    final generation = ++_generation;
    unawaited(_subscription?.cancel());
    try {
      _subscription = _repository
          .watchDailyChoice(_id)
          .listen(
            (result) {
              if (generation != _generation) return;
              switch (result) {
                case GraphResultSuccess(:final value):
                  final revision = value.revision;
                  if (_acceptedRevision != null &&
                      revision.compareTo(_acceptedRevision!) ==
                          GraphRevisionOrder.older) {
                    return;
                  }
                  _acceptedRevision = revision;
                  final details = value.value;
                  _setState(
                    details == null
                        ? const DailyChoiceDetailsNotFound()
                        : DailyChoiceDetailsLoaded(details, revision),
                  );
                case GraphResultFailure(:final failure):
                  _setState(switch (failure) {
                    DailyChoiceReadCorruptionFailure() =>
                      const DailyChoiceDetailsCorruption(),
                    DailyChoiceReadUnavailableFailure() =>
                      const DailyChoiceDetailsUnavailable(),
                    DailyChoiceReadUnexpectedFailure() =>
                      const DailyChoiceDetailsUnexpected(),
                  });
              }
            },
            onError: (Object _, StackTrace _) {
              if (generation == _generation) {
                _setState(const DailyChoiceDetailsUnexpected());
              }
            },
          );
    } catch (_) {
      _setState(const DailyChoiceDetailsUnexpected());
    }
  }

  void _setState(DailyChoiceDetailsState next) {
    _state = next;
    notifyListeners();
  }

  @override
  void dispose() {
    ++_generation;
    unawaited(_subscription?.cancel());
    super.dispose();
  }
}
