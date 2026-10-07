import 'package:flutter/foundation.dart';

import '../../graph/application/graph_command_coordinator.dart';
import '../../graph/application/graph_command_result.dart';
import '../application/daily_choice_result.dart';
import '../domain/daily_choice_id.dart';

/// Идентичность одного входа в создание, независимая от участников и пути.
final class DailyChoiceCreationFlowId {
  DailyChoiceCreationFlowId._();
}

sealed class DailyChoiceCreationFlowState {
  const DailyChoiceCreationFlowState();
}

/// Состояние записи отдельно от права продолжать покинутый поток.
sealed class DailyChoiceCreationFlowActiveState
    extends DailyChoiceCreationFlowState {
  const DailyChoiceCreationFlowActiveState();
}

final class DailyChoiceCreationFlowEditing
    extends DailyChoiceCreationFlowActiveState {
  const DailyChoiceCreationFlowEditing();
}

final class DailyChoiceCreationFlowSubmitting
    extends DailyChoiceCreationFlowActiveState {
  const DailyChoiceCreationFlowSubmitting(this.operation);

  final DailyChoiceCommandAccepted operation;
}

final class DailyChoiceCreationFlowSaved
    extends DailyChoiceCreationFlowActiveState {
  const DailyChoiceCreationFlowSaved(this.choiceId);

  final DailyChoiceId choiceId;
}

/// Поздний результат уточняет запись, но не возвращает право продолжения.
final class DailyChoiceCreationFlowLeft extends DailyChoiceCreationFlowState {
  const DailyChoiceCreationFlowLeft(this.lastActiveState);

  final DailyChoiceCreationFlowActiveState lastActiveState;
}

/// Состояние одного создания, общее для корня, подтверждения и завершения.
///
/// Сборка передаёт идентичности экземпляров маршрутов и снимок истории до
/// корня. Каждая оставшаяся страница и выполняющаяся операция завершения
/// удерживают эту же сессию обычной ссылкой; удаление отдельной страницы не
/// освобождает её и не сбрасывает успех. После исчезновения всех владельцев
/// сессия освобождается сборщиком мусора. Глобального реестра нет.
///
/// Сессия не выполняет команды, не предъявляет результаты и не меняет стек.
/// Вспомогательные пересчёт и замена пути такую сессию не создают.
final class DailyChoiceCreationFlowSession {
  DailyChoiceCreationFlowSession({
    required this.rootMatchId,
    required Iterable<LocalKey> originalHistory,
  }) : originalHistory = List.unmodifiable(originalHistory);

  final DailyChoiceCreationFlowId flowId = DailyChoiceCreationFlowId._();
  final LocalKey rootMatchId;
  final List<LocalKey> originalHistory;
  final DailyChoiceCreationFormKey _formKey = DailyChoiceCreationFormKey();

  // Неизменяемые варианты состояния уведомляют при замене значения:
  // https://api.flutter.dev/flutter/foundation/ValueNotifier-class.html
  final _state = ValueNotifier<DailyChoiceCreationFlowState>(
    const DailyChoiceCreationFlowEditing(),
  );
  var _accepting = false;

  DailyChoiceCreationFlowState get state => _state.value;
  ValueListenable<DailyChoiceCreationFlowState> get changes => _state;

  /// Проверяется перед правкой пути и открытием подтверждения, в том числе
  /// после асинхронного возврата. Проверка отправки дополнительно встроена
  /// в [acceptSubmission]. Ошибки полей и допустимость повтора остаются у формы.
  bool get canContinue =>
      !_accepting && state is DailyChoiceCreationFlowEditing;

  /// Синхронно вызывает принятие команды координатором только у живого
  /// редактируемого потока. Отклонённый вызов не выполняется и не ставится
  /// в очередь. Один ключ формы сохраняется при повторном подтверждении.
  ///
  /// [accept] передаёт команду в acceptDailyChoiceCreation; принятая операция
  /// фиксируется до возврата вызывающей стороне и до любого await. Отмена,
  /// обработанная раньше, исключает вызов [accept]; выход после принятия
  /// оставляет операцию у координатора.
  DailyChoiceCommandStart? acceptSubmission(
    DailyChoiceCommandStart Function(DailyChoiceCreationFormKey) accept,
  ) {
    if (!canContinue) return null;
    _accepting = true;
    try {
      final start = accept(_formKey);
      if (start case DailyChoiceCommandAccepted()) {
        _setActiveState(DailyChoiceCreationFlowSubmitting(start));
      }
      return start;
    } finally {
      _accepting = false;
    }
  }

  /// Фиксирует только результат собственной принятой команды создания.
  ///
  /// Обработчик операции удерживает сессию и вызывает этот метод до проверки
  /// смонтированности формы, события навигации и удаления страниц. Возврат
  /// подтверждения и обновление пути не являются завершениями команды.
  /// Отказ возвращает живой поток к явным действиям; правила исправления и
  /// предъявления ошибки остаются у формы и координатора. У покинутого потока
  /// результат сохраняется внутри Left без восстановления прав или навигации.
  bool recordCompletion(DailyChoiceCommandCompletion completion) {
    final active = switch (state) {
      DailyChoiceCreationFlowActiveState value => value,
      DailyChoiceCreationFlowLeft(:final lastActiveState) => lastActiveState,
    };
    if (active is! DailyChoiceCreationFlowSubmitting ||
        !identical(active.operation.token, completion.token) ||
        completion.kind != DailyChoiceCommandKind.create) {
      return false;
    }
    final next = switch (completion.result) {
      GraphResultSuccess(value: DailyChoiceCreated(:final choice)) =>
        DailyChoiceCreationFlowSaved(choice.id),
      GraphResultFailure() => const DailyChoiceCreationFlowEditing(),
      GraphResultSuccess() => null,
    };
    if (next == null) return false;
    _setActiveState(next);
    return true;
  }

  /// Прекращает продолжение и автоматический переход до удаления маршрутов.
  /// Повторный выход после частичного отказа удаления не возобновляет поток.
  /// Закрытие одного подтверждения этот метод не вызывает; закрытие корня —
  /// вызывает. Принятая команда и право предъявления здесь не освобождаются.
  bool leave() {
    switch (state) {
      case DailyChoiceCreationFlowActiveState value:
        _state.value = DailyChoiceCreationFlowLeft(value);
        return true;
      case DailyChoiceCreationFlowLeft():
        return false;
    }
  }

  void _setActiveState(DailyChoiceCreationFlowActiveState next) {
    _state.value = switch (state) {
      DailyChoiceCreationFlowActiveState() => next,
      DailyChoiceCreationFlowLeft() => DailyChoiceCreationFlowLeft(next),
    };
  }
}
