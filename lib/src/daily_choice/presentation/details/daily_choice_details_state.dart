import '../../../graph/application/graph_command_coordinator.dart';
import '../../../graph/application/graph_revision.dart';
import '../../application/daily_choice_details.dart';
import '../../application/daily_choice_result.dart';

sealed class DailyChoiceDetailsState {
  const DailyChoiceDetailsState();
}

final class DailyChoiceDetailsLoading extends DailyChoiceDetailsState {
  const DailyChoiceDetailsLoading();
}

final class DailyChoiceDetailsLoaded extends DailyChoiceDetailsState {
  const DailyChoiceDetailsLoaded(this.details, this.revision);

  final DailyChoiceDetails details;
  final GraphRevision revision;
}

final class DailyChoiceDetailsNotFound extends DailyChoiceDetailsState {
  const DailyChoiceDetailsNotFound();
}

/// Собственная команда панели подтвердила удаление выбора. Модель больше не
/// наблюдает его и хранит последнее загруженное содержимое для закрытия.
final class DailyChoiceDetailsDeleted extends DailyChoiceDetailsState {
  const DailyChoiceDetailsDeleted(this.details);

  final DailyChoiceDetails details;
}

final class DailyChoiceDetailsUnavailable extends DailyChoiceDetailsState {
  const DailyChoiceDetailsUnavailable();
}

final class DailyChoiceDetailsCorruption extends DailyChoiceDetailsState {
  const DailyChoiceDetailsCorruption();
}

final class DailyChoiceDetailsUnexpected extends DailyChoiceDetailsState {
  const DailyChoiceDetailsUnexpected();
}

/// Записывающая операция выбора. Живёт отдельно от снимка: новые значения
/// приходят только из подписки, а отказ снимает только следующая операция.
sealed class DailyChoiceDetailsOperation {
  const DailyChoiceDetailsOperation();
}

final class DailyChoiceDetailsOperationIdle
    extends DailyChoiceDetailsOperation {
  const DailyChoiceDetailsOperationIdle();
}

final class DailyChoiceDetailsOperationWriting
    extends DailyChoiceDetailsOperation {
  const DailyChoiceDetailsOperationWriting();
}

/// Собственное изменение подтверждено, но подписка ещё не показала снимок с
/// ревизией не старше [revision]. Панель недоступна, как во время записи.
final class DailyChoiceDetailsOperationAwaitingSnapshot
    extends DailyChoiceDetailsOperation {
  const DailyChoiceDetailsOperationAwaitingSnapshot(this.revision);

  final GraphRevision revision;
}

final class DailyChoiceDetailsOperationFailed
    extends DailyChoiceDetailsOperation {
  const DailyChoiceDetailsOperationFailed(
    this.failure, {
    this.failurePresentation,
  });

  final DailyChoiceCommandFailure failure;
  final GraphInitiatorPresentationClaim? failurePresentation;
}
