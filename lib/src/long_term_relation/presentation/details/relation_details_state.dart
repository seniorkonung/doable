import '../../../graph/application/graph_command_coordinator.dart';
import '../../application/long_term_relation_command.dart';
import '../../application/long_term_relation_projection.dart';

/// Состояние подробного просмотра одной долговременной связи.
///
/// Чтение, подтверждённое отсутствие и каждая безопасная категория отказа
/// остаются отдельными вариантами, поэтому ошибка не изображается пустым
/// результатом, а отсутствие — временным сбоем.
sealed class RelationDetailsState {
  const RelationDetailsState({required this.isOperationRunning});

  /// Выполняется ли изменяющая операция с этой связью вне времени жизни экрана.
  final bool isOperationRunning;

  /// Доступен ли пользователю обычный повтор чтения.
  bool get canRetry => false;
}

/// Первое чтение подробных данных ещё не завершилось.
final class RelationDetailsLoading extends RelationDetailsState {
  const RelationDetailsLoading({required super.isOperationRunning});
}

/// Подтверждённые подробные данные связи на одной ревизии графа.
final class RelationDetailsLoaded extends RelationDetailsState {
  const RelationDetailsLoaded({
    required this.details,
    required super.isOperationRunning,
    this.refreshStatus = const RelationDetailsFresh(),
    this.lifecycleChange,
  });

  final LongTermRelationDetails details;
  final RelationDetailsRefreshStatus refreshStatus;
  final RelationDetailsLifecycleChange? lifecycleChange;

  @override
  bool get canRetry => refreshStatus.canRetry;

  RelationDetailsLoaded copyWith({
    LongTermRelationDetails? details,
    bool? isOperationRunning,
    RelationDetailsRefreshStatus? refreshStatus,
    RelationDetailsLifecycleChange? lifecycleChange,
    bool clearLifecycleChange = false,
  }) => RelationDetailsLoaded(
    details: details ?? this.details,
    isOperationRunning: isOperationRunning ?? this.isOperationRunning,
    refreshStatus: refreshStatus ?? this.refreshStatus,
    lifecycleChange: clearLifecycleChange
        ? null
        : lifecycleChange ?? this.lifecycleChange,
  );
}

/// Самостоятельное изменение жизненного цикла конкретной связи.
enum RelationDetailsLifecycleKind { archive, restore, delete }

/// Состояние команды архивирования, восстановления или удаления в просмотре.
sealed class RelationDetailsLifecycleChange {
  const RelationDetailsLifecycleChange(this.kind);

  final RelationDetailsLifecycleKind kind;
}

/// Команда принята общим координатором и ещё выполняется.
final class RelationDetailsLifecycleRunning
    extends RelationDetailsLifecycleChange {
  const RelationDetailsLifecycleRunning(super.kind);
}

/// Команда завершилась безопасно классифицированным отказом.
final class RelationDetailsLifecycleFailed
    extends RelationDetailsLifecycleChange {
  const RelationDetailsLifecycleFailed(
    super.kind,
    this.failure, {
    this.failurePresentation,
  });

  final LongTermRelationCommandFailure failure;

  /// Право открытого просмотра предъявить ошибку по видимому кадру.
  final GraphInitiatorPresentationClaim? failurePresentation;

  bool get canRetry => failure is LongTermRelationUnavailableFailure;
}

/// Чтение подтвердило, что связи больше нет.
final class RelationDetailsNotFound extends RelationDetailsState {
  const RelationDetailsNotFound({required super.isOperationRunning});
}

/// Подтверждённое удаление завершило контекст прежней связи.
final class RelationDetailsDeleted extends RelationDetailsState {
  const RelationDetailsDeleted() : super(isOperationRunning: false);
}

/// Временная недоступность хранилища: повтор уместен.
final class RelationDetailsUnavailable extends RelationDetailsState {
  const RelationDetailsUnavailable({required super.isOperationRunning});

  @override
  bool get canRetry => true;
}

/// Сохранённые данные связи повреждены; повтор не восстановит их.
final class RelationDetailsCorruption extends RelationDetailsState {
  const RelationDetailsCorruption({required super.isOperationRunning});
}

/// Безопасный исход неизвестного отказа чтения.
final class RelationDetailsUnexpected extends RelationDetailsState {
  const RelationDetailsUnexpected({required super.isOperationRunning});
}

/// Состояние согласования уже подтверждённого цельного снимка связи.
sealed class RelationDetailsRefreshStatus {
  const RelationDetailsRefreshStatus();

  bool get canRetry => false;
}

/// Показанный снимок актуален.
final class RelationDetailsFresh extends RelationDetailsRefreshStatus {
  const RelationDetailsFresh();
}

/// Новый цельный снимок ещё читается; прежний остаётся доступен.
final class RelationDetailsRefreshing extends RelationDetailsRefreshStatus {
  const RelationDetailsRefreshing();
}

/// Обновление временно недоступно, поэтому пользователь может повторить его.
final class RelationDetailsRefreshUnavailable
    extends RelationDetailsRefreshStatus {
  const RelationDetailsRefreshUnavailable();

  @override
  bool get canRetry => true;
}

/// Новое чтение обнаружило повреждение; прежний подтверждённый снимок сохранён.
final class RelationDetailsRefreshCorruption
    extends RelationDetailsRefreshStatus {
  const RelationDetailsRefreshCorruption();
}

/// Новое чтение завершилось неизвестным отказом без потери прежнего снимка.
final class RelationDetailsRefreshUnexpected
    extends RelationDetailsRefreshStatus {
  const RelationDetailsRefreshUnexpected();
}
