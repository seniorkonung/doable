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

  /// Файл снимка графа не прошёл проверку при чтении: размер или SHA-256 не
  /// совпали с реестром снимков, файла нет или его записи не читаются.
  snapshotCorruption,
  incompatibleSchema,
  unexpected,
}

/// Этап обращения к настройке режима быстрого создания.
enum QuickCreationModeDiagnosticsStage { read, write }

/// Отказ настройки установки, отдельный от команд и результатов личного графа.
///
/// Событие принимает только этап и безопасный отказ с длительностью и категорией.
/// Содержимое файла, пользовательский текст, пути и исходные исключения
/// не входят в контракт. Передача получателю — через [recordDiagnosticsSafely].
final class QuickCreationModeDiagnosticsEvent extends DiagnosticsEvent {
  const QuickCreationModeDiagnosticsEvent({
    required this.stage,
    required DiagnosticsFailed status,
  }) : super(status);

  final QuickCreationModeDiagnosticsStage stage;
}

enum IntentionCommandDiagnosticsType {
  create,
  update,
  enableReadiness,
  disableReadiness,
  archive,
  restore,
  delete,
}

/// Этап создания намерения вместе с его начальной готовностью
/// и назначениями тегов.
enum IntentionCreationCommandDiagnosticsStage {
  /// Проверка текста и наличия выбранных тегов до любой записи.
  validation,

  /// Запись намерения и назначений тегов.
  write,

  /// Чтение и проверка окончательного результата и подтверждение транзакции.
  resultRead,
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

/// Чтение состояний дней: исход, длительность и безопасная категория отказа.
///
/// Даты, диапазон, идентификаторы, пользовательский текст и исходное исключение
/// не входят в контракт события.
final class DailyChoiceDayStatusesReadDiagnosticsEvent
    extends DiagnosticsEvent {
  const DailyChoiceDayStatusesReadDiagnosticsEvent({
    required DiagnosticsStatus status,
  }) : super(status);
}

/// Вид чтения статистики, без его условий и пользовательских данных.
enum StatisticsReadDiagnosticsType { homePage, intentionSection, breakdown }

enum StatisticsReadDiagnosticsStage {
  /// Чтение агрегатов или исходных данных для подсчёта.
  sourceData,

  relationSnapshot,
  computation,

  /// Чтение названий и архивных состояний отображаемой порции.
  titles,
}

/// Чтение статистики: вид, этап, исход, длительность и категория отказа.
///
/// Пользовательский текст, идентификаторы, даты, период, числа статистики
/// и исходное исключение не входят в контракт события.
/// Передача получателю — через [recordDiagnosticsSafely].
final class StatisticsReadDiagnosticsEvent extends DiagnosticsEvent {
  const StatisticsReadDiagnosticsEvent({
    required this.readType,
    required this.stage,
    required DiagnosticsStatus status,
  }) : super(status);

  final StatisticsReadDiagnosticsType readType;
  final StatisticsReadDiagnosticsStage stage;
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
/// Событие несёт только вид команды, этап, исход, длительность и безопасную
/// категорию отказа: текста, идентификаторов, тегов,
/// SQL и места хранения в нём нет.
///
/// Конструкторы допускают только согласованные сочетания вида команды и
/// этапа: этап есть только у создания.
final class IntentionCommandDiagnosticsEvent extends DiagnosticsEvent {
  /// Команда намерения, кроме создания.
  const IntentionCommandDiagnosticsEvent({
    required this.commandType,
    required DiagnosticsStatus status,
  }) : assert(
         commandType != IntentionCommandDiagnosticsType.create,
         'Создание несёт этап.',
       ),
       stage = null,
       super(status);

  /// Окончательный исход создания намерения на этапе [stage].
  ///
  /// Событие описывает единственный исход команды, а не её начало. Успешное
  /// создание проходит все этапы, поэтому завершается проверкой результата.
  const IntentionCommandDiagnosticsEvent.create({
    required IntentionCreationCommandDiagnosticsStage this.stage,
    required DiagnosticsStatus status,
  }) : assert(
         status is! DiagnosticsStarted,
         'Событие создания описывает окончательный исход.',
       ),
       assert(
         status is! DiagnosticsSucceeded ||
             stage == IntentionCreationCommandDiagnosticsStage.resultRead,
         'Успешное создание завершается проверкой результата.',
       ),
       commandType = IntentionCommandDiagnosticsType.create,
       super(status);

  final IntentionCommandDiagnosticsType commandType;
  final IntentionCreationCommandDiagnosticsStage? stage;
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

/// Этап записи снимка графа.
enum GraphSnapshotWriteDiagnosticsStage {
  /// Сборка состояния из прежнего снимка и пакетов фактов после него.
  stateAssembly,

  /// Надёжная запись файла снимка под окончательным именем.
  fileWrite,

  /// Регистрация снимка в реестре снимков.
  registration,
}

/// Запись снимка графа: исход, длительность, а у отказа — этап и безопасная
/// категория, в том числе повреждение прежнего снимка.
///
/// Позиции лога, имена и пути файлов, содержимое снимка и исходное
/// исключение не входят в контракт события. Конструкторы допускают этап
/// только у отказа. Передача получателю — через [recordDiagnosticsSafely].
final class GraphSnapshotWriteDiagnosticsEvent extends DiagnosticsEvent {
  GraphSnapshotWriteDiagnosticsEvent.succeeded({required Duration duration})
    : stage = null,
      super(DiagnosticsSucceeded(duration));

  GraphSnapshotWriteDiagnosticsEvent.failed({
    required GraphSnapshotWriteDiagnosticsStage this.stage,
    required Duration duration,
    required DiagnosticsFailureCode code,
  }) : super(DiagnosticsFailed(duration: duration, code: code));

  final GraphSnapshotWriteDiagnosticsStage? stage;
}

/// Этап пересборки снимка графа из базы.
enum GraphSnapshotRebuildDiagnosticsStage {
  /// Чтение записей графа из базы порциями во временный файл.
  databaseRead,

  /// Сборка состояния из временного файла и пакетов фактов после первой
  /// порции.
  stateAssembly,

  /// Надёжная запись файла снимка под окончательным именем.
  fileWrite,

  /// Регистрация снимка в реестре снимков.
  registration,
}

/// Пересборка снимка графа из базы после того, как последний снимок не
/// прошёл проверку: исход, длительность, а у отказа — этап и безопасная
/// категория.
///
/// Позиции лога, имена и пути файлов, записи графа и исходное исключение не
/// входят в контракт события. Конструкторы допускают этап только у отказа.
/// Передача получателю — через [recordDiagnosticsSafely].
final class GraphSnapshotRebuildDiagnosticsEvent extends DiagnosticsEvent {
  GraphSnapshotRebuildDiagnosticsEvent.succeeded({required Duration duration})
    : stage = null,
      super(DiagnosticsSucceeded(duration));

  GraphSnapshotRebuildDiagnosticsEvent.failed({
    required GraphSnapshotRebuildDiagnosticsStage this.stage,
    required Duration duration,
    required DiagnosticsFailureCode code,
  }) : super(DiagnosticsFailed(duration: duration, code: code));

  final GraphSnapshotRebuildDiagnosticsStage? stage;
}

/// Этап фонового сжатия лога фактов.
enum GraphLogCompactionDiagnosticsStage {
  /// Сверка числа пакетов после последнего снимка с порогом сжатия.
  check,

  /// Запись снимка в отдельном изоляте, в том числе его пересборка из базы.
  snapshotWrite,

  /// Удаление истории до нового снимка.
  historyRemoval,
}

/// Сжатие лога фактов в снимок: исход, длительность, а у отказа — этап и
/// безопасная категория. Сверка, после которой сжатие не понадобилось,
/// события не даёт.
///
/// Позиции лога, пороги, имена и пути файлов и исходное исключение не входят
/// в контракт события. Конструкторы допускают этап только у отказа.
/// Передача получателю — через [recordDiagnosticsSafely].
final class GraphLogCompactionDiagnosticsEvent extends DiagnosticsEvent {
  GraphLogCompactionDiagnosticsEvent.succeeded({required Duration duration})
    : stage = null,
      super(DiagnosticsSucceeded(duration));

  GraphLogCompactionDiagnosticsEvent.failed({
    required GraphLogCompactionDiagnosticsStage this.stage,
    required Duration duration,
    required DiagnosticsFailureCode code,
  }) : super(DiagnosticsFailed(duration: duration, code: code));

  final GraphLogCompactionDiagnosticsStage? stage;
}

/// Этап очистки каталога снимков.
enum GraphSnapshotCleanupDiagnosticsStage {
  /// Чтение имён файлов зарегистрированных снимков.
  registryRead,

  /// Удаление незарегистрированных и временных файлов каталога.
  fileRemoval,
}

/// Очистка каталога снимков от незарегистрированных и временных файлов:
/// исход, длительность, а у отказа — этап и безопасная категория.
///
/// Имена и пути файлов, их число и исходное исключение не входят в контракт
/// события. Конструкторы допускают этап только у отказа. Передача
/// получателю — через [recordDiagnosticsSafely].
final class GraphSnapshotCleanupDiagnosticsEvent extends DiagnosticsEvent {
  GraphSnapshotCleanupDiagnosticsEvent.succeeded({required Duration duration})
    : stage = null,
      super(DiagnosticsSucceeded(duration));

  GraphSnapshotCleanupDiagnosticsEvent.failed({
    required GraphSnapshotCleanupDiagnosticsStage this.stage,
    required Duration duration,
    required DiagnosticsFailureCode code,
  }) : super(DiagnosticsFailed(duration: duration, code: code));

  final GraphSnapshotCleanupDiagnosticsStage? stage;
}
