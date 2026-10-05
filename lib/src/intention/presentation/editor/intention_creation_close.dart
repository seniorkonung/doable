import '../../../graph/application/graph_command_coordinator.dart';

/// Что закрытие сессии создания означает для её отправки; определяет
/// объяснение, которое получает человек.
enum IntentionCreationSavingOnClose {
  /// Принятой отправки нет: закрытие не создаёт намерение.
  notStarted,

  /// Принятая отправка выполняется: закрытие её не отменяет, сохранение
  /// продолжится, а результат предъявляется по общему протоколу.
  continues,
}

/// Единственное подтверждение закрытия изменённого черновика одной сессии.
///
/// Действует, только пока остаётся ожидающим подтверждением выдавшего его
/// построения сессии с ключом [formKey]. Ответ на него, смена состояния
/// отправки и завершение сессии делают его недействительным: запоздалый ответ
/// ничего не меняет и не закрывает другую или вновь открытую сессию.
final class IntentionCreationCloseConfirmation {
  // Не const: подтверждения различаются идентичностью даже при одинаковых
  // данных, поэтому прежнее не совпадает с выданным позднее.
  IntentionCreationCloseConfirmation({
    required this.formKey,
    required this.savingOnClose,
  });

  final IntentionCreationFormKey formKey;

  /// Состояние отправки, для которого выдано подтверждение и которое оно
  /// объясняет.
  final IntentionCreationSavingOnClose savingOnClose;
}

/// Решение сессии о запросе закрытия, единое для всех способов ухода.
sealed class IntentionCreationCloseDecision {
  const IntentionCreationCloseDecision();
}

/// Черновик не изменён: сессия уже завершена без подтверждения, и её панель
/// закрывается сразу.
final class IntentionCreationClosedImmediately
    extends IntentionCreationCloseDecision {
  const IntentionCreationClosedImmediately(this.savingOnClose);

  final IntentionCreationSavingOnClose savingOnClose;
}

/// Черновик изменён: закрытие требует одного явного подтверждения.
final class IntentionCreationCloseNeedsConfirmation
    extends IntentionCreationCloseDecision {
  const IntentionCreationCloseNeedsConfirmation(this.confirmation);

  final IntentionCreationCloseConfirmation confirmation;
}

/// Подтверждение этой сессии уже ожидает ответа; второе не создаётся.
final class IntentionCreationCloseAwaitingConfirmation
    extends IntentionCreationCloseDecision {
  const IntentionCreationCloseAwaitingConfirmation();
}

/// Сессия уже завершена успешным созданием, закрытием или освобождением;
/// запрос ничего не закрывает.
final class IntentionCreationCloseSessionEnded
    extends IntentionCreationCloseDecision {
  const IntentionCreationCloseSessionEnded();
}

/// Ответ человека на подтверждение закрытия.
enum IntentionCreationCloseChoice {
  /// Продолжить ввод: панель и все данные черновика сохраняются.
  continueEditing,

  /// Сбросить черновик и закрыть панель. Принятая отправка продолжается.
  discardDraft,
}

/// Исход ответа на подтверждение закрытия.
enum IntentionCreationCloseResolution {
  /// Сессия продолжается со всеми данными черновика.
  continued,

  /// Сессия завершена сбросом черновика; её панель закрывается.
  closed,

  /// Подтверждение больше не действует; ответ ничего не меняет и ничего не
  /// закрывает.
  outdated,
}

/// Ход закрытия сессии создания.
sealed class IntentionCreationClosing {
  const IntentionCreationClosing();
}

/// Закрытие не запрошено или ожидавшее подтверждение больше не действует.
final class IntentionCreationCloseNotRequested
    extends IntentionCreationClosing {
  const IntentionCreationCloseNotRequested();
}

/// Ожидается ответ на единственное подтверждение закрытия.
final class IntentionCreationCloseConfirming extends IntentionCreationClosing {
  const IntentionCreationCloseConfirming(this.confirmation);

  final IntentionCreationCloseConfirmation confirmation;
}

/// Сессия завершена запросом закрытия: сразу либо подтверждённым сбросом.
final class IntentionCreationClosedOnRequest extends IntentionCreationClosing {
  const IntentionCreationClosedOnRequest();
}
