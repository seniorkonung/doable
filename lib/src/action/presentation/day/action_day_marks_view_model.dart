import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../graph/application/graph_command_coordinator.dart';
import '../../../graph/application/graph_command_result.dart';
import '../../../graph/application/graph_revision.dart';
import '../../../graph/application/personal_graph_repository.dart';
import '../../../graph/application/personal_graph_repository_provider.dart';
import '../../application/action_day_statuses.dart';
import 'action_day_marks_state.dart';
import 'action_day_marks_window.dart';
import 'action_day_calendar_viewport.dart';
import 'action_day_instance.dart';

part 'action_day_marks_view_model.g.dart';

/// Причина передачи просмотра модели отметок.
enum ActionDayCalendarViewportUpdateReason {
  /// Обычная установка просмотра, включая смену недели или представления.
  ordinary,

  /// Пользователь завершил выбор месяца, даже если просмотр не изменился.
  monthSelectionCompleted,
}

/// Отметки периода, независимые от выбранного дня и выдачи экрана дня.
/// Страница удерживает провайдер с ключом своего экземпляра всё время
/// своей жизни и передаёт изменения просмотра через [setViewport].
@riverpod
final class ActionDayMarksViewModel extends _$ActionDayMarksViewModel {
  late PersonalGraphRepository _repository;
  late ActionDayCalendarViewport _viewport;
  late ActionDayStatusQuery _window;
  GraphRevision? _requiredRevision;
  Object? _lifetime;
  var _isReading = false;
  var _readAgain = false;

  @override
  ActionDayMarksState build(ActionDayInstance instance) {
    _repository = ref.watch(personalGraphRepositoryProvider);
    _viewport = ActionDayCalendarViewport(
      focusedDate: instance.initialDate,
      mode: ActionDayCalendarMode.week,
    );
    _window = actionDayMarksWindow(instance.initialDate);
    _requiredRevision = null;
    final lifetime = _lifetime = Object();
    _isReading = false;
    final coordinator = ref.watch(graphCommandCoordinatorProvider.notifier);
    final completions = coordinator.completions.listen((completion) {
      scheduleMicrotask(() {
        if (ref.mounted && identical(lifetime, _lifetime)) {
          _onCompletion(completion);
        }
      });
    });
    ref.onDispose(() {
      _lifetime = null;
      unawaited(completions.cancel());
    });
    _requestRead();
    return const ActionDayMarksState();
  }

  /// После отказа изменение просмотра или завершённый выбор месяца
  /// повторяет чтение. Обычная установка равного просмотра бездействует.
  void setViewport(
    ActionDayCalendarViewport viewport, {
    ActionDayCalendarViewportUpdateReason reason =
        ActionDayCalendarViewportUpdateReason.ordinary,
  }) {
    if (_viewport == viewport &&
        reason == ActionDayCalendarViewportUpdateReason.ordinary) {
      return;
    }
    final previousDate = _viewport.focusedDate;
    _viewport = viewport;
    final date = viewport.focusedDate;
    final monthChanged =
        previousDate.year != date.year || previousDate.month != date.month;
    if (monthChanged) _window = actionDayMarksWindow(date);
    if (monthChanged || state.hasReadFailure) _requestRead();
  }

  void _requestRead() {
    _readAgain = true;
    if (_isReading) return;
    _isReading = true;
    unawaited(_read(_lifetime));
  }

  void _onCompletion(GraphCommandCompletion completion) {
    final package = completion.confirmedChange;
    if (package == null) return;
    final known = _requiredRevision;
    if (known != null) {
      final order = package.revision.compareTo(known);
      if (order == GraphRevisionOrder.older ||
          order == GraphRevisionOrder.same) {
        return;
      }
    }
    _requiredRevision = package.revision;
    _requestRead();
  }

  Future<void> _read(Object? lifetime) async {
    while (_readAgain) {
      _readAgain = false;
      final query = _window;
      final result = await _repository.getActionDayStatuses(query);
      if (!ref.mounted || !identical(lifetime, _lifetime)) return;
      if (!identical(query, _window)) {
        _readAgain = true;
        continue;
      }
      switch (result) {
        case GraphResultSuccess(:final value):
          if (_precedesRequired(value.revision)) {
            _readAgain = true;
            continue;
          }
          _requiredRevision = value.revision;
          _readAgain = false;
          state = ActionDayMarksState(dayStatuses: value.value);
        case GraphResultFailure():
          state = ActionDayMarksState(
            dayStatuses: state.dayStatuses,
            hasReadFailure: true,
          );
      }
    }
    _isReading = false;
  }

  bool _precedesRequired(GraphRevision revision) {
    final required = _requiredRevision;
    if (required == null) return false;
    final order = revision.compareTo(required);
    return order == GraphRevisionOrder.older ||
        order == GraphRevisionOrder.differentEpoch;
  }
}
