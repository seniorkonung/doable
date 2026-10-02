abstract interface class DiagnosticsSink {
  /// Выполняет best-effort запись и не выпускает ошибки в вызывающий код.
  void record(DiagnosticsEvent event);
}

/// Однократно передаёт событие получателю, не позволяя диагностике изменить
/// исход наблюдаемой операции.
void recordDiagnosticsSafely(DiagnosticsSink? sink, DiagnosticsEvent event) {
  try {
    sink?.record(event);
  } on Object {
    // Повторная диагностическая запись здесь изменила бы исход и семантику.
  }
}

sealed class DiagnosticsEvent {
  const DiagnosticsEvent(this.status);

  final DiagnosticsStatus status;
}

sealed class DiagnosticsStatus {
  const DiagnosticsStatus();
}

final class DiagnosticsStarted extends DiagnosticsStatus {
  const DiagnosticsStarted();
}

final class DiagnosticsSucceeded extends DiagnosticsStatus {
  const DiagnosticsSucceeded(this.duration);

  final Duration duration;
}

final class DiagnosticsFailed extends DiagnosticsStatus {
  const DiagnosticsFailed({required this.duration, required this.code});

  final Duration duration;
  final DiagnosticsFailureCode code;
}

enum DiagnosticsFailureCode {
  validation,
  notFound,
  conflict,
  unavailable,
  corruption,
  incompatibleSchema,
  unexpected,
}

enum IntentionCommandDiagnosticsType {
  create,
  update,
  enableReadiness,
  disableReadiness,
  archive,
  restore,
  delete,
  markFavorite,
  unmarkFavorite,
}

/// Этап команды отметки избранного или её снятия.
enum FavoriteMarkCommandDiagnosticsStage {
  /// Проверка существования намерения и его текущей отметки.
  validation,

  /// Запись отметки и подтверждение её результата.
  write,
}

enum LongTermRelationCommandDiagnosticsType {
  create,
  update,
  archive,
  restore,
  delete,
}

enum DailyChoicePathCommandDiagnosticsType { create, replacePath }

enum DailyChoiceCommandDiagnosticsType {
  create,
  updateFields,
  replacePath,
  delete,
}

enum DailyChoiceCommandDiagnosticsStage { validation, write, resultRead }

enum TagCommandDiagnosticsType {
  create,
  rename,
  delete,
  assign,
  removeAssignment,
}

enum TagCommandDiagnosticsStage { validation, write, resultRead }

enum TagReadDiagnosticsStage { validation, read }

final class TagCommandDiagnosticsEvent extends DiagnosticsEvent {
  const TagCommandDiagnosticsEvent({
    required this.commandType,
    required this.stage,
    required DiagnosticsStatus status,
  }) : super(status);

  final TagCommandDiagnosticsType commandType;
  final TagCommandDiagnosticsStage stage;
}

final class TagCatalogReadDiagnosticsEvent extends DiagnosticsEvent {
  const TagCatalogReadDiagnosticsEvent({
    required this.stage,
    required DiagnosticsStatus status,
  }) : super(status);

  final TagReadDiagnosticsStage stage;
}

final class TagAssignmentsReadDiagnosticsEvent extends DiagnosticsEvent {
  const TagAssignmentsReadDiagnosticsEvent({
    required this.stage,
    required DiagnosticsStatus status,
  }) : super(status);

  final TagReadDiagnosticsStage stage;
}

final class TaggedEntitiesPageReadDiagnosticsEvent extends DiagnosticsEvent {
  const TaggedEntitiesPageReadDiagnosticsEvent({
    required this.stage,
    required DiagnosticsStatus status,
  }) : super(status);

  final TagReadDiagnosticsStage stage;
}

final class TagAssignmentStatusReadDiagnosticsEvent extends DiagnosticsEvent {
  const TagAssignmentStatusReadDiagnosticsEvent({
    required this.stage,
    required DiagnosticsStatus status,
  }) : super(status);

  final TagReadDiagnosticsStage stage;
}

final class TagDetailReadDiagnosticsEvent extends DiagnosticsEvent {
  const TagDetailReadDiagnosticsEvent({
    required this.stage,
    required DiagnosticsStatus status,
  }) : super(status);

  final TagReadDiagnosticsStage stage;
}

final class DailyChoiceReadDiagnosticsEvent extends DiagnosticsEvent {
  const DailyChoiceReadDiagnosticsEvent({required DiagnosticsStatus status})
    : super(status);
}

enum ChoicePathSuggestionReadStage { candidateSelection, pathValidation }

final class ChoicePathSuggestionReadDiagnosticsEvent extends DiagnosticsEvent {
  const ChoicePathSuggestionReadDiagnosticsEvent({
    required this.stage,
    required DiagnosticsStatus status,
  }) : super(status);

  final ChoicePathSuggestionReadStage stage;
}

final class DailyChoiceCatalogPageReadDiagnosticsEvent
    extends DiagnosticsEvent {
  const DailyChoiceCatalogPageReadDiagnosticsEvent({
    required this.pageSize,
    required this.isContinuation,
    required DiagnosticsStatus status,
  }) : super(status);

  final int pageSize;
  final bool isContinuation;
}

enum ChoicePathContinuationReadStage { validation, read }

final class ChoicePathContinuationReadDiagnosticsEvent
    extends DiagnosticsEvent {
  const ChoicePathContinuationReadDiagnosticsEvent({
    required this.stage,
    required this.pageSize,
    required this.isContinuation,
    required DiagnosticsStatus status,
  }) : super(status);

  final ChoicePathContinuationReadStage stage;
  final int pageSize;
  final bool isContinuation;
}

final class DailyChoicePathValidationDiagnosticsEvent extends DiagnosticsEvent {
  const DailyChoicePathValidationDiagnosticsEvent({
    required this.commandType,
    required DiagnosticsStatus status,
  }) : super(status);

  final DailyChoicePathCommandDiagnosticsType commandType;
}

final class DailyChoiceCommandDiagnosticsEvent extends DiagnosticsEvent {
  const DailyChoiceCommandDiagnosticsEvent({
    required this.commandType,
    required this.stage,
    required DiagnosticsStatus status,
  }) : super(status);

  final DailyChoiceCommandDiagnosticsType commandType;
  final DailyChoiceCommandDiagnosticsStage stage;
}

final class BootstrapDiagnosticsEvent extends DiagnosticsEvent {
  const BootstrapDiagnosticsEvent({
    required DiagnosticsStatus status,
    this.schemaVersion,
  }) : super(status);

  final int? schemaVersion;
}

final class MigrationDiagnosticsEvent extends DiagnosticsEvent {
  const MigrationDiagnosticsEvent({
    required this.fromSchemaVersion,
    required this.toSchemaVersion,
    required DiagnosticsStatus status,
  }) : super(status);

  final int fromSchemaVersion;
  final int toSchemaVersion;
}

final class CatalogPageReadDiagnosticsEvent extends DiagnosticsEvent {
  const CatalogPageReadDiagnosticsEvent({
    required this.pageSize,
    required DiagnosticsStatus status,
  }) : super(status);

  final int pageSize;
}

/// Вид успешного завершения чтения согласования каталога.
enum CatalogReconciliationReadCompletion {
  /// Получена порция недостающих совпадений.
  portion,

  /// Граф изменился после начала согласования; его нужно повторить.
  retry,
}

/// Чтение согласования каталога, отдельное от обычной порции каталога.
///
/// Конструкторы допускают только согласованные сочетания статуса и вида
/// завершения: вид есть ровно у успешно завершённого чтения.
final class CatalogReconciliationReadDiagnosticsEvent extends DiagnosticsEvent {
  const CatalogReconciliationReadDiagnosticsEvent.started({
    required this.pageSize,
  }) : completion = null,
       super(const DiagnosticsStarted());

  CatalogReconciliationReadDiagnosticsEvent.completed({
    required this.pageSize,
    required Duration duration,
    required CatalogReconciliationReadCompletion this.completion,
  }) : super(DiagnosticsSucceeded(duration));

  CatalogReconciliationReadDiagnosticsEvent.failed({
    required this.pageSize,
    required Duration duration,
    required DiagnosticsFailureCode code,
  }) : completion = null,
       super(DiagnosticsFailed(duration: duration, code: code));

  final int pageSize;
  final CatalogReconciliationReadCompletion? completion;
}

final class IntentionDetailReadDiagnosticsEvent extends DiagnosticsEvent {
  const IntentionDetailReadDiagnosticsEvent({required DiagnosticsStatus status})
    : super(status);
}

final class RelationCountsReadDiagnosticsEvent extends DiagnosticsEvent {
  const RelationCountsReadDiagnosticsEvent({required DiagnosticsStatus status})
    : super(status);
}

final class RelationGroupPageReadDiagnosticsEvent extends DiagnosticsEvent {
  const RelationGroupPageReadDiagnosticsEvent({
    required this.pageSize,
    required this.isContinuation,
    required this.requiresNewSnapshot,
    required DiagnosticsStatus status,
  }) : super(status);

  final int pageSize;
  final bool isContinuation;
  final bool requiresNewSnapshot;
}

final class DailyChoiceGroupPageReadDiagnosticsEvent extends DiagnosticsEvent {
  const DailyChoiceGroupPageReadDiagnosticsEvent({
    required this.pageSize,
    required this.isContinuation,
    required this.requiresNewSnapshot,
    required DiagnosticsStatus status,
  }) : super(status);

  final int pageSize;
  final bool isContinuation;
  final bool requiresNewSnapshot;
}

final class LongTermRelationDetailReadDiagnosticsEvent
    extends DiagnosticsEvent {
  const LongTermRelationDetailReadDiagnosticsEvent({
    required DiagnosticsStatus status,
  }) : super(status);
}

final class SelectedRelationsReadDiagnosticsEvent extends DiagnosticsEvent {
  const SelectedRelationsReadDiagnosticsEvent({
    required DiagnosticsStatus status,
  }) : super(status);
}

/// Команда намерения.
///
/// Конструкторы допускают только согласованные сочетания вида команды и
/// этапа: этап есть ровно у отметки избранного и её снятия.
final class IntentionCommandDiagnosticsEvent extends DiagnosticsEvent {
  /// Команда намерения, кроме отметки избранного и её снятия.
  const IntentionCommandDiagnosticsEvent({
    required this.commandType,
    required DiagnosticsStatus status,
  }) : assert(
         commandType != IntentionCommandDiagnosticsType.markFavorite &&
             commandType != IntentionCommandDiagnosticsType.unmarkFavorite,
         'Отметка избранного и её снятие несут этап.',
       ),
       stage = null,
       super(status);

  const IntentionCommandDiagnosticsEvent.markFavorite({
    required FavoriteMarkCommandDiagnosticsStage this.stage,
    required DiagnosticsStatus status,
  }) : commandType = IntentionCommandDiagnosticsType.markFavorite,
       super(status);

  const IntentionCommandDiagnosticsEvent.unmarkFavorite({
    required FavoriteMarkCommandDiagnosticsStage this.stage,
    required DiagnosticsStatus status,
  }) : commandType = IntentionCommandDiagnosticsType.unmarkFavorite,
       super(status);

  final IntentionCommandDiagnosticsType commandType;
  final FavoriteMarkCommandDiagnosticsStage? stage;
}

final class LongTermRelationCommandDiagnosticsEvent extends DiagnosticsEvent {
  const LongTermRelationCommandDiagnosticsEvent({
    required this.commandType,
    required DiagnosticsStatus status,
  }) : super(status);

  final LongTermRelationCommandDiagnosticsType commandType;
}

final class BlockingRelationsDeleteDiagnosticsEvent extends DiagnosticsEvent {
  const BlockingRelationsDeleteDiagnosticsEvent({
    required DiagnosticsStatus status,
  }) : super(status);
}
