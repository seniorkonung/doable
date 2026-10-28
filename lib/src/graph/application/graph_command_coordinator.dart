import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../daily_choice/application/daily_choice_command.dart';
import '../../daily_choice/application/daily_choice_result.dart';
import '../../daily_choice/domain/daily_choice_id.dart';
import '../../graph_backups/graph_backups.dart';
import '../../intention/application/intention_command.dart';
import '../../intention/application/intention_catalog.dart';
import '../../intention/application/intention_result.dart';
import '../../intention/domain/intention_id.dart';
import '../../long_term_relation/application/long_term_relation_command.dart';
import '../../long_term_relation/domain/long_term_relation_id.dart';
import '../../tag/application/tag_command.dart';
import '../../tag/application/tag_result.dart';
import '../../tag/domain/tag_id.dart';
import 'graph_change.dart';
import 'graph_command_result.dart';
import 'graph_revision.dart';
import 'personal_graph_repository.dart';
import 'personal_graph_repository_provider.dart';

part 'graph_command_coordinator.g.dart';

enum IntentionCommandKind {
  create,
  update,
  enableReadiness,
  disableReadiness,
  archive,
  restore,
  delete,
}

sealed class GraphCommandKey {
  const GraphCommandKey();
}

final class IntentionCreationFormKey extends GraphCommandKey {
  IntentionCreationFormKey();
}

final class ExistingIntentionKey extends GraphCommandKey {
  const ExistingIntentionKey(this.intentionId);

  final IntentionId intentionId;

  @override
  bool operator ==(Object other) =>
      other is ExistingIntentionKey && other.intentionId == intentionId;

  @override
  int get hashCode => intentionId.hashCode;
}

final class LongTermRelationCreationFormKey extends GraphCommandKey {
  LongTermRelationCreationFormKey();
}

final class ExistingLongTermRelationKey extends GraphCommandKey {
  const ExistingLongTermRelationKey(this.relationId);

  final LongTermRelationId relationId;

  @override
  bool operator ==(Object other) =>
      other is ExistingLongTermRelationKey && other.relationId == relationId;

  @override
  int get hashCode => relationId.hashCode;
}

final class DailyChoiceCreationFormKey extends GraphCommandKey {
  DailyChoiceCreationFormKey();
}

final class ExistingDailyChoiceKey extends GraphCommandKey {
  const ExistingDailyChoiceKey(this.choiceId);

  final DailyChoiceId choiceId;

  @override
  bool operator ==(Object other) =>
      other is ExistingDailyChoiceKey && other.choiceId == choiceId;

  @override
  int get hashCode => Object.hash(ExistingDailyChoiceKey, choiceId);
}

final class TagCreationFormKey extends GraphCommandKey {
  TagCreationFormKey();
}

final class ExistingTagKey extends GraphCommandKey {
  const ExistingTagKey(this.tagId);

  final TagId tagId;

  @override
  bool operator ==(Object other) =>
      other is ExistingTagKey && other.tagId == tagId;

  @override
  int get hashCode => Object.hash(ExistingTagKey, tagId);
}

sealed class GraphOperationToken {
  const GraphOperationToken();
}

final class IntentionOperationToken extends GraphOperationToken {
  IntentionOperationToken._();

  @override
  String toString() => 'IntentionOperationToken';
}

final class LongTermRelationOperationToken extends GraphOperationToken {
  LongTermRelationOperationToken._();

  @override
  String toString() => 'LongTermRelationOperationToken';
}

final class DailyChoiceOperationToken extends GraphOperationToken {
  DailyChoiceOperationToken._();

  @override
  String toString() => 'DailyChoiceOperationToken';
}

final class TagOperationToken extends GraphOperationToken {
  TagOperationToken._();

  @override
  String toString() => 'TagOperationToken';
}

final class GraphExportOperationToken extends GraphOperationToken {
  GraphExportOperationToken._();

  @override
  String toString() => 'GraphExportOperationToken';
}

final class GraphBackupRestoreOperationToken extends GraphOperationToken {
  GraphBackupRestoreOperationToken._();

  @override
  String toString() => 'GraphBackupRestoreOperationToken';
}

final class GraphImportOperationToken extends GraphOperationToken {
  GraphImportOperationToken._();

  @override
  String toString() => 'GraphImportOperationToken';
}

final class GraphManualBackupOperationToken extends GraphOperationToken {
  GraphManualBackupOperationToken._();

  @override
  String toString() => 'GraphManualBackupOperationToken';
}

/// Завершение принятой операции, которое coordinator публикует для
/// согласования данных.
sealed class GraphCommandCompletion {
  const GraphCommandCompletion();

  GraphOperationToken get token;
  ConfirmedGraphChangePackage? get confirmedChange;

  GraphRevision? get revision => confirmedChange?.revision;

  /// Отличает отказ от успеха без знания конкретной предметной операции.
  bool get isFailure;
}

/// Завершение, право предъявления которого выдаёт coordinator.
///
/// Политику предъявления задаёт вид завершения. По умолчанию действует
/// протокол ADR-0012: успех сразу принадлежит оболочке, а отказ — открытой
/// экранной сессии инициатора. У операции с политикой «только отказ» по
/// ADR-0016 отказ сразу принадлежит оболочке. У политики «успех без сообщения»
/// по ADR-0046 отказ сохраняет протокол ADR-0012. Обе политики исключают
/// успешное завершение из этого типа.
sealed class GraphPresentableCompletion extends GraphCommandCompletion {
  const GraphPresentableCompletion();
}

sealed class IntentionCommandCompletion extends GraphCommandCompletion {
  const IntentionCommandCompletion._({
    required this.token,
    required this.kind,
    required this.target,
    required this.confirmedResult,
  });

  @override
  final IntentionOperationToken token;
  final IntentionCommandKind kind;
  final IntentionOperationTarget target;
  final Result<ConfirmedGraphResult<IntentionCommandSuccess>> confirmedResult;

  Result<IntentionCommandSuccess> get result => switch (confirmedResult) {
    ResultSuccess(:final value) => ResultSuccess(value.value),
    ResultFailure(:final failure) => ResultFailure(failure),
  };

  @override
  ConfirmedGraphChangePackage? get confirmedChange => switch (confirmedResult) {
    ResultSuccess(:final value) => value,
    ResultFailure() => null,
  };

  @override
  bool get isFailure => switch (confirmedResult) {
    ResultSuccess() => false,
    ResultFailure() => true,
  };

  String? get presentationTitle => switch (result) {
    ResultSuccess(value: IntentionSaved(:final intention)) => intention.title,
    ResultSuccess(value: IntentionDeleted()) ||
    ResultFailure() => switch (target) {
      ExistingIntentionOperationTarget(:final title) => title,
      CreatingIntentionOperationTarget() => null,
    },
  };
}

final class IntentionPresentableCompletion extends IntentionCommandCompletion
    implements GraphPresentableCompletion {
  const IntentionPresentableCompletion._({
    required super.token,
    required super.kind,
    required super.target,
    required super.confirmedResult,
  }) : super._();
}

/// Успех изменения текста публикуется только для согласования данных.
/// Отказ этой операции остаётся предъявляемым по ADR-0012.
final class IntentionUpdateSucceededCompletion
    extends IntentionCommandCompletion {
  const IntentionUpdateSucceededCompletion._({
    required super.token,
    required super.target,
    required ResultSuccess<ConfirmedGraphResult<IntentionCommandSuccess>>
    result,
  }) : super._(kind: IntentionCommandKind.update, confirmedResult: result);
}

enum LongTermRelationCommandKind { create, update, archive, restore, delete }

final class LongTermRelationCommandCompletion
    extends GraphPresentableCompletion {
  const LongTermRelationCommandCompletion._({
    required this.token,
    required this.kind,
    required this.target,
    required this.confirmedResult,
  });

  @override
  final LongTermRelationOperationToken token;
  final LongTermRelationCommandKind kind;
  final LongTermRelationOperationTarget target;
  final LongTermRelationCommandResult confirmedResult;

  GraphResult<LongTermRelationCommandSuccess, LongTermRelationCommandFailure>
  get result => switch (confirmedResult) {
    GraphResultSuccess(:final value) => GraphResultSuccess(value.value),
    GraphResultFailure(:final failure) => GraphResultFailure(failure),
  };

  @override
  ConfirmedGraphChangePackage? get confirmedChange => switch (confirmedResult) {
    GraphResultSuccess(:final value) => value,
    GraphResultFailure() => null,
  };

  @override
  bool get isFailure => switch (confirmedResult) {
    GraphResultSuccess() => false,
    GraphResultFailure() => true,
  };
}

enum DailyChoiceCommandKind { create, update, replace, delete }

final class DailyChoiceCommandCompletion extends GraphPresentableCompletion {
  const DailyChoiceCommandCompletion._({
    required this.token,
    required this.kind,
    required this.confirmedResult,
  });

  @override
  final DailyChoiceOperationToken token;
  final DailyChoiceCommandKind kind;
  final DailyChoiceCommandResult confirmedResult;

  GraphResult<DailyChoiceCommandSuccess, DailyChoiceCommandFailure>
  get result => switch (confirmedResult) {
    GraphResultSuccess(:final value) => GraphResultSuccess(value.value),
    GraphResultFailure(:final failure) => GraphResultFailure(failure),
  };

  @override
  ConfirmedGraphChangePackage? get confirmedChange => switch (confirmedResult) {
    GraphResultSuccess(:final value) => value,
    GraphResultFailure() => null,
  };

  @override
  bool get isFailure => confirmedResult is GraphResultFailure;
}

enum TagCommandKind { create, update, delete, move, assign, removeAssignment }

/// Завершение операции тега с политикой «только отказ» по ADR-0016.
///
/// Подтверждённый результат создания, изменения, удаления, перестановки,
/// назначения и снятия назначения виден там, где операция выполнена, поэтому
/// успех публикуется для согласования и права предъявления не образует, а
/// отказ сразу принадлежит общей поверхности.
sealed class TagCommandCompletion extends GraphCommandCompletion {
  const TagCommandCompletion._({required this.token, required this.kind});

  @override
  final TagOperationToken token;
  final TagCommandKind kind;

  TagCommandResult get confirmedResult;

  GraphResult<TagCommandSuccess, TagCommandFailure> get result =>
      switch (confirmedResult) {
        GraphResultSuccess(:final value) => GraphResultSuccess(value.value),
        GraphResultFailure(:final failure) => GraphResultFailure(failure),
      };
}

final class TagCommandSucceededCompletion extends TagCommandCompletion {
  const TagCommandSucceededCompletion._({
    required super.token,
    required super.kind,
    required this.confirmedResult,
  }) : super._();

  @override
  final TagCommandSucceeded confirmedResult;

  @override
  ConfirmedGraphChangePackage get confirmedChange => confirmedResult.value;

  @override
  bool get isFailure => false;
}

final class TagCommandFailedCompletion extends TagCommandCompletion
    implements GraphPresentableCompletion {
  const TagCommandFailedCompletion._({
    required super.token,
    required super.kind,
    required this.confirmedResult,
  }) : super._();

  @override
  final TagCommandFailed confirmedResult;

  TagCommandFailure get failure => confirmedResult.failure;

  @override
  ConfirmedGraphChangePackage? get confirmedChange => null;

  @override
  bool get isFailure => true;
}

/// Исход экспорта графа, выполненного модулем операций с данными.
enum GraphExportOutcome {
  succeeded,
  failed,

  /// Человек выбрал в системном диалоге файл с данными, и экспорт не начат,
  /// чтобы не перезаписать его.
  existingFile,
}

/// Завершение экспорта графа в файл.
///
/// Права инициатора у экспорта нет: успех и отказ сразу принадлежат общей
/// поверхности. Выбор файла с данными предъявляется так же, как отказ. Граф
/// экспорт не меняет, поэтому пакета изменений у него нет.
final class GraphExportCompletion extends GraphPresentableCompletion {
  const GraphExportCompletion._({
    required this.token,
    required this.outcome,
    required this.retry,
  });

  @override
  final GraphExportOperationToken token;
  final GraphExportOutcome outcome;

  /// Повтор экспорта, переданный при его принятии.
  final void Function() retry;

  @override
  ConfirmedGraphChangePackage? get confirmedChange => null;

  @override
  bool get isFailure => switch (outcome) {
    GraphExportOutcome.succeeded => false,
    GraphExportOutcome.failed || GraphExportOutcome.existingFile => true,
  };
}

/// Исход восстановления копии, выполненного модулем операций с данными.
sealed class GraphBackupRestoreOutcome {
  const GraphBackupRestoreOutcome();
}

/// Человек отменил восстановление: граф и копии остались прежними, а
/// сообщения нет.
final class GraphBackupRestoreCancelled extends GraphBackupRestoreOutcome {
  const GraphBackupRestoreCancelled();
}

/// Исход восстановления, который предъявляется сообщением.
sealed class GraphBackupRestoreResult extends GraphBackupRestoreOutcome {
  const GraphBackupRestoreResult();
}

/// Граф заменён состоянием копии.
///
/// Этот исход даёт только замена в монопольном режиме координатора —
/// [GraphExclusiveReplacement.replace] принятого восстановления.
final class GraphBackupRestored extends GraphBackupRestoreResult {
  const GraphBackupRestored._(this.replacement);

  final ConfirmedGraphReplacement replacement;
}

/// Восстановление не удалось, и граф и копии остались прежними.
final class GraphBackupRestoreFailed extends GraphBackupRestoreResult {
  const GraphBackupRestoreFailed();
}

/// Восстановлению не хватило места на устройстве, и граф и копии остались
/// прежними.
final class GraphBackupRestoreStorageFull extends GraphBackupRestoreResult {
  const GraphBackupRestoreStorageFull();
}

/// Завершение восстановления копии.
///
/// Успех сразу принадлежит общей поверхности, а отказ — сначала строке
/// «Резервные копии» через право инициатора. Отмена завершения не даёт.
final class GraphBackupRestoreCompletion extends GraphPresentableCompletion {
  const GraphBackupRestoreCompletion._({
    required this.token,
    required this.result,
  });

  @override
  final GraphBackupRestoreOperationToken token;
  final GraphBackupRestoreResult result;

  /// Изменение «граф заменён» успешного восстановления.
  @override
  ConfirmedGraphChangePackage? get confirmedChange => switch (result) {
    GraphBackupRestored(:final replacement) => replacement,
    GraphBackupRestoreFailed() || GraphBackupRestoreStorageFull() => null,
  };

  @override
  bool get isFailure => switch (result) {
    GraphBackupRestored() => false,
    GraphBackupRestoreFailed() || GraphBackupRestoreStorageFull() => true,
  };
}

/// Исход импорта файла экспорта, выполненного модулем операций с данными.
sealed class GraphImportOutcome {
  const GraphImportOutcome();
}

/// Человек отменил импорт: граф и копии остались прежними, а сообщения нет.
final class GraphImportCancelled extends GraphImportOutcome {
  const GraphImportCancelled();
}

/// Исход импорта, который предъявляется сообщением.
sealed class GraphImportResult extends GraphImportOutcome {
  const GraphImportResult();
}

/// Граф заменён содержимым файла экспорта.
///
/// Этот исход даёт только замена в монопольном режиме координатора —
/// [GraphExclusiveReplacement.replace] принятого импорта.
final class GraphImported extends GraphImportResult {
  const GraphImported._(this.replacement);

  final ConfirmedGraphReplacement replacement;
}

/// Импорт не удался, и граф и копии остались прежними.
final class GraphImportFailed extends GraphImportResult {
  const GraphImportFailed(this.failure);

  final GraphImportFailure failure;
}

/// Категория отказа импорта; от неё зависит, как человек может его
/// исправить.
enum GraphImportFailure {
  /// Файл не является экспортом Doable или повреждён, в том числе нарушает
  /// правила данных графа.
  invalidFile,

  /// Файл создан более новой версией формата, чем поддерживает приложение.
  newerFormatVersion,

  /// На устройстве не хватило места.
  storageFull,

  /// Выбранный документ не прочитан: поставщик не открыл его или чтение
  /// прервалось.
  documentUnreadable,

  /// Причину нельзя отнести ни к одной другой категории.
  unknown,
}

/// Завершение импорта файла экспорта.
///
/// Успех сразу принадлежит общей поверхности, а отказ — сначала строке
/// «Импорт данных» через право инициатора. Отмена завершения не даёт.
final class GraphImportCompletion extends GraphPresentableCompletion {
  const GraphImportCompletion._({required this.token, required this.result});

  @override
  final GraphImportOperationToken token;
  final GraphImportResult result;

  /// Изменение «граф заменён» успешного импорта.
  @override
  ConfirmedGraphChangePackage? get confirmedChange => switch (result) {
    GraphImported(:final replacement) => replacement,
    GraphImportFailed() => null,
  };

  @override
  bool get isFailure => switch (result) {
    GraphImported() => false,
    GraphImportFailed() => true,
  };
}

/// Завершение ручной копии с политикой «только отказ» по ADR-0016.
///
/// Новая копия видна в списке копий и в строке «Резервные копии», поэтому
/// успех публикуется для согласования и права предъявления не образует, а
/// отказ сразу принадлежит общей поверхности. Граф копия не меняет, поэтому
/// пакета изменений у неё нет.
sealed class GraphManualBackupCompletion extends GraphCommandCompletion {
  const GraphManualBackupCompletion._(this.token);

  @override
  final GraphManualBackupOperationToken token;

  @override
  ConfirmedGraphChangePackage? get confirmedChange => null;
}

final class GraphManualBackupMadeCompletion
    extends GraphManualBackupCompletion {
  const GraphManualBackupMadeCompletion._(super.token) : super._();

  @override
  bool get isFailure => false;
}

final class GraphManualBackupFailedCompletion
    extends GraphManualBackupCompletion
    implements GraphPresentableCompletion {
  const GraphManualBackupFailedCompletion._(super.token) : super._();

  @override
  bool get isFailure => true;
}

/// Право принятой замены графа — импорта или восстановления копии — заменить
/// граф в монопольном режиме координатора; [R] — успешный исход этой
/// операции.
final class GraphExclusiveReplacement<R> {
  GraphExclusiveReplacement._(this._coordinator, this._replaced);

  final GraphCommandCoordinator _coordinator;
  final R Function(ConfirmedGraphReplacement replacement) _replaced;

  /// Входит в монопольный режим, дожидается завершения команд, принятых
  /// раньше, и выполняет замену графа [replace].
  ///
  /// В монопольном режиме новые команды графа не принимаются: их начало —
  /// [GraphCommandCoordinatorDraining]. Режим длится до публикации исхода
  /// замены, поэтому завершения команд, принятых после замены, публикуются
  /// позже завершения «граф заменён». Исключение [replace] передаётся
  /// вызывающему.
  Future<R> replace(
    Future<ConfirmedGraphReplacement> Function() replace,
  ) async => _replaced(await _coordinator._replaceExclusively(replace));
}

sealed class IntentionOperationTarget {
  const IntentionOperationTarget();
}

final class CreatingIntentionOperationTarget extends IntentionOperationTarget {
  const CreatingIntentionOperationTarget();
}

final class ExistingIntentionOperationTarget extends IntentionOperationTarget {
  const ExistingIntentionOperationTarget({
    required this.intentionId,
    required this.title,
  });

  final IntentionId intentionId;
  final String title;
}

sealed class LongTermRelationOperationTarget {
  const LongTermRelationOperationTarget();
}

final class CreatingLongTermRelationOperationTarget
    extends LongTermRelationOperationTarget {
  const CreatingLongTermRelationOperationTarget();
}

final class ExistingLongTermRelationOperationTarget
    extends LongTermRelationOperationTarget {
  const ExistingLongTermRelationOperationTarget(this.relationId);

  final LongTermRelationId relationId;
}

sealed class IntentionCommandStart {
  const IntentionCommandStart();
}

final class IntentionCommandAccepted extends IntentionCommandStart {
  const IntentionCommandAccepted({required this.token, required this.future});

  final IntentionOperationToken token;
  final Future<IntentionCommandCompletion> future;
}

final class IntentionCommandAlreadyRunning extends IntentionCommandStart {
  const IntentionCommandAlreadyRunning();
}

sealed class LongTermRelationCommandStart {
  const LongTermRelationCommandStart();
}

final class LongTermRelationCommandAccepted
    extends LongTermRelationCommandStart {
  const LongTermRelationCommandAccepted({
    required this.token,
    required this.future,
  });

  final LongTermRelationOperationToken token;
  final Future<LongTermRelationCommandCompletion> future;
}

final class LongTermRelationCommandAlreadyRunning
    extends LongTermRelationCommandStart {
  const LongTermRelationCommandAlreadyRunning();
}

sealed class DailyChoiceCommandStart {
  const DailyChoiceCommandStart();
}

final class DailyChoiceCommandAccepted extends DailyChoiceCommandStart {
  const DailyChoiceCommandAccepted({required this.token, required this.future});

  final DailyChoiceOperationToken token;
  final Future<DailyChoiceCommandCompletion> future;
}

final class DailyChoiceCommandAlreadyRunning extends DailyChoiceCommandStart {
  const DailyChoiceCommandAlreadyRunning();
}

sealed class TagCommandStart {
  const TagCommandStart();
}

final class TagCommandAccepted extends TagCommandStart {
  const TagCommandAccepted({required this.token, required this.future});

  final TagOperationToken token;
  final Future<TagCommandCompletion> future;
}

final class TagCommandAlreadyRunning extends TagCommandStart {
  const TagCommandAlreadyRunning();
}

sealed class GraphExportStart {
  const GraphExportStart();
}

final class GraphExportAccepted extends GraphExportStart {
  const GraphExportAccepted(this.future);

  final Future<GraphExportCompletion> future;
}

final class GraphExportAlreadyRunning extends GraphExportStart {
  const GraphExportAlreadyRunning();
}

sealed class GraphBackupRestoreStart {
  const GraphBackupRestoreStart();
}

final class GraphBackupRestoreAccepted extends GraphBackupRestoreStart {
  const GraphBackupRestoreAccepted({required this.token, required this.future});

  final GraphBackupRestoreOperationToken token;

  /// Исход восстановления, в том числе отмена; завершение, если оно есть, к
  /// этому моменту уже опубликовано.
  final Future<GraphBackupRestoreOutcome> future;
}

sealed class GraphImportStart {
  const GraphImportStart();
}

final class GraphImportAccepted extends GraphImportStart {
  const GraphImportAccepted({required this.token, required this.future});

  final GraphImportOperationToken token;

  /// Исход импорта, в том числе отмена; завершение, если оно есть, к этому
  /// моменту уже опубликовано.
  final Future<GraphImportOutcome> future;
}

/// Координатор не принимает замену графа: идёт другая — импорт или
/// восстановление копии.
final class GraphReplacementAlreadyRunning extends GraphBackupRestoreStart
    implements GraphImportStart {
  const GraphReplacementAlreadyRunning();
}

sealed class GraphManualBackupStart {
  const GraphManualBackupStart();
}

final class GraphManualBackupAccepted extends GraphManualBackupStart {
  const GraphManualBackupAccepted(this.future);

  final Future<GraphManualBackupCompletion> future;
}

final class GraphManualBackupAlreadyRunning extends GraphManualBackupStart {
  const GraphManualBackupAlreadyRunning();
}

/// Координатор не принимает операцию: идёт завершение работы приложения, а
/// для команд графа — и замена графа в монопольном режиме. Экраны
/// предъявляют оба случая одинаково.
final class GraphCommandCoordinatorDraining extends IntentionCommandStart
    implements
        LongTermRelationCommandStart,
        DailyChoiceCommandStart,
        TagCommandStart,
        GraphExportStart,
        GraphBackupRestoreStart,
        GraphImportStart,
        GraphManualBackupStart {
  const GraphCommandCoordinatorDraining();
}

/// Право открытой экранной сессии предъявить собственную ошибку.
final class GraphInitiatorPresentationClaim {
  const GraphInitiatorPresentationClaim._(
    this.token,
    this.completion,
    this._entry,
  );

  final GraphOperationToken token;
  final GraphPresentableCompletion completion;
  final _PresentationEntry _entry;
}

/// Право оболочки на зафиксированный набор ожидающих результатов.
///
/// Удержание права не означает предъявления: после доступного кадра
/// подтверждаются только результаты, охваченные показанным сообщением.
final class GraphAppPresentationClaim {
  GraphAppPresentationClaim._(
    List<_PresentationEntry> entries,
    this._registration,
  ) : _entries = List.unmodifiable(entries),
      completions = List.unmodifiable(
        entries.map((entry) => entry.completion!),
      );

  final List<GraphPresentableCompletion> completions;
  final List<_PresentationEntry> _entries;
  final GraphAppPresentationRegistration _registration;
}

/// Регистрация получателя общего app-канала предъявления.
///
/// Одновременно выдачу получает только самая ранняя действующая регистрация,
/// и у неё не больше одного неподтверждённого claim. Освобождение возвращает
/// coordinator выданный неподтверждённый claim и ожидающий запрос.
final class GraphAppPresentationRegistration {
  GraphAppPresentationRegistration._(this._coordinator);

  final GraphCommandCoordinator _coordinator;
  Completer<GraphAppPresentationClaim?>? _request;
  GraphAppPresentationClaim? _issued;
  var _isReleased = false;

  /// Запрашивает все ожидающие app-результаты в порядке публикации.
  ///
  /// Возвращает `null`, если регистрация освобождена или coordinator завершил
  /// работу до выдачи.
  Future<GraphAppPresentationClaim?> nextClaim() =>
      _coordinator._requestAppClaim(this);

  void release() => _coordinator._releaseRegistration(this);
}

@Riverpod(keepAlive: true)
final class GraphCommandCoordinator extends _$GraphCommandCoordinator {
  final _completionController =
      StreamController<GraphCommandCompletion>.broadcast(sync: true);
  // Запись переставляется в конец при публикации завершения, поэтому порядок
  // записей совпадает с порядком публикации terminal outcome: завершения
  // команд публикуются последовательно в порядке принятия, а экспорта,
  // импорта, восстановления копии и отказа ручной копии — вне этой
  // последовательности.
  final _entries = <GraphOperationToken, _PresentationEntry>{};
  final _registrations = <GraphAppPresentationRegistration>[];
  final _gates = <GraphCommandKey, _PresentationEntry>{};
  final _inFlight = <Future<void>>{};
  late GraphCommandRepository _repository;
  Future<void> _publicationTail = Future<void>.value();
  var _isDraining = false;
  var _isExportRunning = false;

  /// Принята замена графа — импорт или восстановление копии, — исход которой
  /// ещё не опубликован.
  var _hasAcceptedReplacement = false;
  var _isManualBackupRunning = false;

  /// Монопольный режим замены графа: новые команды графа не принимаются.
  var _isReplacing = false;
  Completer<void>? _shutdownCompleter;

  @override
  void build() {
    _repository = ref.watch(personalGraphRepositoryProvider);
  }

  Stream<GraphCommandCompletion> get completions =>
      _completionController.stream;

  Stream<IntentionCommandCompletion> get intentionCompletions =>
      _completionController.stream
          .where((completion) => completion is IntentionCommandCompletion)
          .map((completion) => completion as IntentionCommandCompletion);

  bool isRunning(IntentionId intentionId) =>
      isKeyRunning(ExistingIntentionKey(intentionId));

  bool isRelationRunning(LongTermRelationId relationId) =>
      isKeyRunning(ExistingLongTermRelationKey(relationId));

  bool isDailyChoiceRunning(DailyChoiceId choiceId) =>
      isKeyRunning(ExistingDailyChoiceKey(choiceId));

  bool isTagRunning(TagId tagId) => isKeyRunning(ExistingTagKey(tagId));

  bool isKeyRunning(GraphCommandKey key) => _gates.containsKey(key);

  /// Принимает отправку формы [formKey] вместе со всем начальным состоянием
  /// [command].
  ///
  /// Пока принятая команда выполняется, повтор той же формы не принимается,
  /// не запускается и не ставится в очередь. Уход формы освобождает только её
  /// право предъявления: команда выполняется один раз, а ограничение формы
  /// снимается вместе с публикацией окончательного завершения. Готовность
  /// и назначения входят в пакет этого завершения и отдельных
  /// результатов не образуют. Успех сразу принадлежит общей поверхности,
  /// отказ — сначала живой форме по ADR-0012.
  IntentionCommandStart acceptCreation(
    IntentionCreationFormKey formKey,
    CreateIntention command,
  ) => _accept(formKey, command, const CreatingIntentionOperationTarget());

  IntentionCommandStart acceptExisting(
    ExistingIntentionCommand command, {
    required String presentationTitle,
  }) => _accept(
    ExistingIntentionKey(command.id),
    command,
    ExistingIntentionOperationTarget(
      intentionId: command.id,
      title: presentationTitle,
    ),
  );

  LongTermRelationCommandStart acceptRelationCreation(
    LongTermRelationCreationFormKey formKey,
    CreateLongTermRelation command,
  ) => _acceptRelation(
    key: formKey,
    command: command,
    kind: LongTermRelationCommandKind.create,
    target: const CreatingLongTermRelationOperationTarget(),
  );

  LongTermRelationCommandStart acceptRelationUpdate(
    UpdateLongTermRelation command,
  ) => _acceptRelation(
    key: ExistingLongTermRelationKey(command.relationId),
    command: command,
    kind: LongTermRelationCommandKind.update,
    target: ExistingLongTermRelationOperationTarget(command.relationId),
  );

  LongTermRelationCommandStart acceptRelationArchive(
    ArchiveLongTermRelation command,
  ) => _acceptRelation(
    key: ExistingLongTermRelationKey(command.relationId),
    command: command,
    kind: LongTermRelationCommandKind.archive,
    target: ExistingLongTermRelationOperationTarget(command.relationId),
  );

  LongTermRelationCommandStart acceptRelationRestore(
    RestoreLongTermRelation command,
  ) => _acceptRelation(
    key: ExistingLongTermRelationKey(command.relationId),
    command: command,
    kind: LongTermRelationCommandKind.restore,
    target: ExistingLongTermRelationOperationTarget(command.relationId),
  );

  LongTermRelationCommandStart acceptRelationDelete(
    DeleteLongTermRelation command,
  ) => _acceptRelation(
    key: ExistingLongTermRelationKey(command.relationId),
    command: command,
    kind: LongTermRelationCommandKind.delete,
    target: ExistingLongTermRelationOperationTarget(command.relationId),
  );

  DailyChoiceCommandStart acceptDailyChoiceCreation(
    DailyChoiceCreationFormKey formKey,
    CreateDailyChoice command,
  ) => _acceptDailyChoice(formKey, command, DailyChoiceCommandKind.create);

  DailyChoiceCommandStart acceptDailyChoiceUpdate(
    UpdateDailyChoiceFields command,
  ) => _acceptDailyChoice(
    ExistingDailyChoiceKey(command.choiceId),
    command,
    DailyChoiceCommandKind.update,
  );

  DailyChoiceCommandStart acceptDailyChoiceReplace(
    ReplaceDailyChoicePath command,
  ) => _acceptDailyChoice(
    ExistingDailyChoiceKey(command.choiceId),
    command,
    DailyChoiceCommandKind.replace,
  );

  DailyChoiceCommandStart acceptDailyChoiceDelete(DeleteDailyChoice command) =>
      _acceptDailyChoice(
        ExistingDailyChoiceKey(command.choiceId),
        command,
        DailyChoiceCommandKind.delete,
      );

  TagCommandStart acceptTagCreation(
    TagCreationFormKey formKey,
    CreateTag command,
  ) => _acceptTag({formKey}, command, TagCommandKind.create);

  TagCommandStart acceptTagUpdate(UpdateTag command) => _acceptTag(
    {ExistingTagKey(command.tagId)},
    command,
    TagCommandKind.update,
  );

  TagCommandStart acceptTagDelete(DeleteTag command) => _acceptTag(
    {ExistingTagKey(command.tagId)},
    command,
    TagCommandKind.delete,
  );

  TagCommandStart acceptTagMove(MoveTag command) =>
      _acceptTag({ExistingTagKey(command.tagId)}, command, TagCommandKind.move);

  TagCommandStart acceptTagAssign(AssignTag command) => _acceptTag(
    _assignmentKeys(command.tagId, command.intentionId),
    command,
    TagCommandKind.assign,
  );

  TagCommandStart acceptTagRemoveAssignment(RemoveTagAssignment command) =>
      _acceptTag(
        _assignmentKeys(command.tagId, command.intentionId),
        command,
        TagCommandKind.removeAssignment,
      );

  Set<GraphCommandKey> _assignmentKeys(TagId tagId, IntentionId intentionId) =>
      {ExistingTagKey(tagId), ExistingIntentionKey(intentionId)};

  TagCommandStart _acceptTag(
    Set<GraphCommandKey> keys,
    TagCommand command,
    TagCommandKind kind,
  ) {
    final token = TagOperationToken._();
    final acceptance = _acceptOperation(
      keys: keys,
      // Права инициатора у операций тегов нет: отказ сразу принадлежит
      // оболочке.
      entry: _PresentationEntry(token)..initiatorReleased = true,
      execute: () async => switch (await _executeTag(command)) {
        final TagCommandSucceeded result => TagCommandSucceededCompletion._(
          token: token,
          kind: kind,
          confirmedResult: result,
        ),
        final TagCommandFailed result => TagCommandFailedCompletion._(
          token: token,
          kind: kind,
          confirmedResult: result,
        ),
      },
    );
    return switch (acceptance) {
      _GraphCommandAccepted(:final future) => TagCommandAccepted(
        token: token,
        future: future.then((completion) => completion as TagCommandCompletion),
      ),
      _GraphCommandAlreadyRunning() => const TagCommandAlreadyRunning(),
      _GraphCommandDraining() => const GraphCommandCoordinatorDraining(),
    };
  }

  DailyChoiceCommandStart _acceptDailyChoice(
    GraphCommandKey key,
    DailyChoiceCommand command,
    DailyChoiceCommandKind kind,
  ) {
    final token = DailyChoiceOperationToken._();
    final acceptance = _acceptOperation(
      keys: {key},
      entry: _PresentationEntry(token),
      execute: () async => DailyChoiceCommandCompletion._(
        token: token,
        kind: kind,
        confirmedResult: await _executeDailyChoice(command),
      ),
    );
    return switch (acceptance) {
      _GraphCommandAccepted(:final future) => DailyChoiceCommandAccepted(
        token: token,
        future: future.then(
          (completion) => completion as DailyChoiceCommandCompletion,
        ),
      ),
      _GraphCommandAlreadyRunning() => const DailyChoiceCommandAlreadyRunning(),
      _GraphCommandDraining() => const GraphCommandCoordinatorDraining(),
    };
  }

  LongTermRelationCommandStart _acceptRelation({
    required GraphCommandKey key,
    required LongTermRelationCommand command,
    required LongTermRelationCommandKind kind,
    required LongTermRelationOperationTarget target,
  }) {
    final token = LongTermRelationOperationToken._();
    final acceptance = _acceptOperation(
      keys: {key},
      entry: _PresentationEntry(token),
      execute: () async {
        final result = await _executeLongTermRelation(command);
        return LongTermRelationCommandCompletion._(
          token: token,
          kind: kind,
          target: target,
          confirmedResult: result,
        );
      },
    );
    return switch (acceptance) {
      _GraphCommandAccepted(:final future) => LongTermRelationCommandAccepted(
        token: token,
        future: future.then(
          (completion) => completion as LongTermRelationCommandCompletion,
        ),
      ),
      _GraphCommandAlreadyRunning() =>
        const LongTermRelationCommandAlreadyRunning(),
      _GraphCommandDraining() => const GraphCommandCoordinatorDraining(),
    };
  }

  IntentionCommandStart _accept(
    GraphCommandKey key,
    IntentionCommand command,
    IntentionOperationTarget target,
  ) {
    final token = IntentionOperationToken._();
    final kind = _kindOf(command);
    final acceptance = _acceptOperation(
      keys: {key},
      entry: _PresentationEntry(token),
      execute: () async {
        final result = await _executeIntention(command);
        if (kind == IntentionCommandKind.update &&
            result
                is ResultSuccess<
                  ConfirmedGraphResult<IntentionCommandSuccess>
                >) {
          return IntentionUpdateSucceededCompletion._(
            token: token,
            target: target,
            result: result,
          );
        }
        return IntentionPresentableCompletion._(
          token: token,
          kind: kind,
          target: target,
          confirmedResult: result,
        );
      },
    );
    return switch (acceptance) {
      _GraphCommandAccepted(:final future) => IntentionCommandAccepted(
        token: token,
        future: future.then(
          (completion) => completion as IntentionCommandCompletion,
        ),
      ),
      _GraphCommandAlreadyRunning() => const IntentionCommandAlreadyRunning(),
      _GraphCommandDraining() => const GraphCommandCoordinatorDraining(),
    };
  }

  _GraphCommandAcceptance _acceptOperation({
    required Set<GraphCommandKey> keys,
    required _PresentationEntry entry,
    required Future<GraphCommandCompletion> Function() execute,
  }) {
    if (_isDraining || _isReplacing) {
      return const _GraphCommandDraining();
    }

    if (keys.any(_gates.containsKey)) {
      return const _GraphCommandAlreadyRunning();
    }

    for (final key in keys) {
      _gates[key] = entry;
    }
    _entries[entry.token] = entry;
    final operationFuture = Future<GraphCommandCompletion>.sync(execute);

    final completionCompleter = Completer<GraphCommandCompletion>();
    late final Future<void> tracked;
    final publication = _publicationTail.then<void>((_) async {
      final completion = await operationFuture;
      if (completion is GraphPresentableCompletion) {
        _placeAtPublication(entry, completion);
      } else {
        // Успех политик «только отказ» и «успех без сообщения» не оставляет
        // непредъявленной записи.
        _discardEntry(entry);
      }
      for (final key in keys) {
        if (identical(_gates[key], entry)) {
          _gates.remove(key);
        }
      }
      _completionController.add(completion);
      completionCompleter.complete(completion);
      _dispatchAppPresentation();
    });
    _publicationTail = publication;
    tracked = publication.whenComplete(() {
      _inFlight.remove(tracked);
      _completeShutdownIfDrained();
    });
    _inFlight.add(tracked);

    return _GraphCommandAccepted(completionCompleter.future);
  }

  /// Принимает экспорт графа, который выполняет [export] модуля операций с
  /// данными.
  ///
  /// Пока принятый экспорт выполняется, второй не принимается. Экспорт не
  /// блокирует сущности графа, а его завершение публикуется сразу по
  /// окончании, вне последовательной публикации команд: завершения команд,
  /// принятых во время экспорта, его не ждут. Отказ предъявляется с действием,
  /// которое запускает [retry].
  GraphExportStart acceptExport({
    required Future<GraphExportOutcome> Function() export,
    required void Function() retry,
  }) {
    if (_isDraining) {
      return const GraphCommandCoordinatorDraining();
    }
    if (_isExportRunning) {
      return const GraphExportAlreadyRunning();
    }

    _isExportRunning = true;
    final token = GraphExportOperationToken._();
    // Права инициатора у экспорта нет: результат сразу принадлежит оболочке.
    final entry = _PresentationEntry(token)..initiatorReleased = true;
    _entries[token] = entry;
    late final Future<void> tracked;
    final publication = _runExport(export).then((outcome) {
      final completion = GraphExportCompletion._(
        token: token,
        outcome: outcome,
        retry: retry,
      );
      _placeAtPublication(entry, completion);
      _isExportRunning = false;
      _completionController.add(completion);
      _dispatchAppPresentation();
      return completion;
    });
    tracked = publication.whenComplete(() {
      _inFlight.remove(tracked);
      _completeShutdownIfDrained();
    });
    _inFlight.add(tracked);

    return GraphExportAccepted(publication);
  }

  Future<GraphExportOutcome> _runExport(
    Future<GraphExportOutcome> Function() export,
  ) async {
    try {
      return await export();
    } on Object {
      return GraphExportOutcome.failed;
    }
  }

  /// Принимает восстановление копии, которое выполняет [restore] модуля
  /// операций с данными.
  ///
  /// Подготовка замены идёт без монопольного режима: команды графа
  /// принимаются как обычно. Саму замену [restore] выполняет через
  /// [GraphExclusiveReplacement.replace]. Пока принятая замена графа —
  /// импорт или восстановление — выполняется, восстановление не
  /// принимается. Исключение [restore] становится отказом.
  GraphBackupRestoreStart acceptBackupRestore(
    Future<GraphBackupRestoreOutcome> Function(
      GraphExclusiveReplacement<GraphBackupRestored> exclusive,
    )
    restore,
  ) {
    if (_isDraining) {
      return const GraphCommandCoordinatorDraining();
    }
    if (_hasAcceptedReplacement) {
      return const GraphReplacementAlreadyRunning();
    }

    final token = GraphBackupRestoreOperationToken._();
    return GraphBackupRestoreAccepted(
      token: token,
      future: _runReplacement(
        token,
        () => restore(GraphExclusiveReplacement._(this, GraphBackupRestored._)),
        failed: const GraphBackupRestoreFailed(),
        completionOf: (outcome) => switch (outcome) {
          GraphBackupRestoreCancelled() => null,
          GraphBackupRestoreResult() => GraphBackupRestoreCompletion._(
            token: token,
            result: outcome,
          ),
        },
      ),
    );
  }

  /// Принимает импорт файла экспорта, который выполняет [import] модуля
  /// операций с данными.
  ///
  /// Подготовка замены идёт без монопольного режима: команды графа
  /// принимаются как обычно. Саму замену [import] выполняет через
  /// [GraphExclusiveReplacement.replace]. Исход, известный до замены,
  /// например отказ чтения документа, [import] возвращает сразу, не входя в
  /// монопольный режим. Пока принятая замена графа — импорт или
  /// восстановление копии — выполняется, импорт не принимается. Исключение
  /// [import] становится отказом по неизвестной причине.
  GraphImportStart acceptImport(
    Future<GraphImportOutcome> Function(
      GraphExclusiveReplacement<GraphImported> exclusive,
    )
    import,
  ) {
    if (_isDraining) {
      return const GraphCommandCoordinatorDraining();
    }
    if (_hasAcceptedReplacement) {
      return const GraphReplacementAlreadyRunning();
    }

    final token = GraphImportOperationToken._();
    return GraphImportAccepted(
      token: token,
      future: _runReplacement(
        token,
        () => import(GraphExclusiveReplacement._(this, GraphImported._)),
        failed: const GraphImportFailed(GraphImportFailure.unknown),
        completionOf: (outcome) => switch (outcome) {
          GraphImportCancelled() => null,
          GraphImportResult() => GraphImportCompletion._(
            token: token,
            result: outcome,
          ),
        },
      ),
    );
  }

  /// Выполняет принятую замену графа [replacement] и публикует её завершение
  /// [completionOf] сразу по окончании, вне последовательной публикации
  /// команд; исход без завершения — отмена — права предъявления не
  /// оставляет. Исключение [replacement] становится исходом [failed].
  Future<O> _runReplacement<O>(
    GraphOperationToken token,
    Future<O> Function() replacement, {
    required O failed,
    required GraphPresentableCompletion? Function(O outcome) completionOf,
  }) {
    _hasAcceptedReplacement = true;
    final entry = _PresentationEntry(token);
    _entries[token] = entry;
    late final Future<void> tracked;
    final publication = _settleReplacement(replacement, failed).then((outcome) {
      _hasAcceptedReplacement = false;
      _isReplacing = false;
      switch (completionOf(outcome)) {
        case null:
          _discardEntry(entry);
        case final completion:
          _placeAtPublication(entry, completion);
          _completionController.add(completion);
          _dispatchAppPresentation();
      }
      return outcome;
    });
    tracked = publication.whenComplete(() {
      _inFlight.remove(tracked);
      _completeShutdownIfDrained();
    });
    _inFlight.add(tracked);
    return publication;
  }

  Future<O> _settleReplacement<O>(
    Future<O> Function() replacement,
    O failed,
  ) async {
    try {
      return await replacement();
    } on Object {
      return failed;
    }
  }

  Future<ConfirmedGraphReplacement> _replaceExclusively(
    Future<ConfirmedGraphReplacement> Function() replace,
  ) async {
    _isReplacing = true;
    // Завершения команд публикуются по порядку принятия, а новых команд в
    // монопольном режиме нет, поэтому хвост публикации охватывает все
    // принятые раньше.
    await _publicationTail;
    return replace();
  }

  /// Принимает ручную копию, которую делает [backup] модуля резервных копий;
  /// [backup] сообщает отказ исходом, а не исключением.
  ///
  /// Пока принятая ручная копия выполняется, вторая не принимается. Копия не
  /// блокирует сущности графа, а её завершение публикуется сразу по
  /// окончании, вне последовательной публикации команд. По ADR-0016 успех
  /// права предъявления не образует, а отказ сразу принадлежит общей
  /// поверхности.
  GraphManualBackupStart acceptManualBackup(
    Future<ManualGraphBackupOutcome> Function() backup,
  ) {
    if (_isDraining) {
      return const GraphCommandCoordinatorDraining();
    }
    if (_isManualBackupRunning) {
      return const GraphManualBackupAlreadyRunning();
    }

    _isManualBackupRunning = true;
    final token = GraphManualBackupOperationToken._();
    late final Future<void> tracked;
    final publication = backup().then((outcome) {
      _isManualBackupRunning = false;
      final GraphManualBackupCompletion completion = switch (outcome) {
        ManualGraphBackupOutcome.made => GraphManualBackupMadeCompletion._(
          token,
        ),
        ManualGraphBackupOutcome.failed => GraphManualBackupFailedCompletion._(
          token,
        ),
      };
      if (completion case GraphManualBackupFailedCompletion failure) {
        // Права инициатора у ручной копии нет: отказ сразу принадлежит
        // оболочке.
        _placeAtPublication(
          _PresentationEntry(token)..initiatorReleased = true,
          failure,
        );
      }
      _completionController.add(completion);
      _dispatchAppPresentation();
      return completion;
    });
    tracked = publication.whenComplete(() {
      _inFlight.remove(tracked);
      _completeShutdownIfDrained();
    });
    _inFlight.add(tracked);

    return GraphManualBackupAccepted(publication);
  }

  void _placeAtPublication(
    _PresentationEntry entry,
    GraphPresentableCompletion completion,
  ) {
    entry.completion = completion;
    _entries
      ..remove(entry.token)
      ..[entry.token] = entry;
  }

  /// Выдаёт открытой экранной сессии право предъявить её failure.
  ///
  /// Успех инициатору не выдаётся. После освобождения сессии или выдачи
  /// права оболочке возвращает `null`.
  GraphInitiatorPresentationClaim? claimInitiatorFailure(
    GraphOperationToken token,
  ) {
    final entry = _entries[token];
    final completion = entry?.completion;
    if (entry == null ||
        completion == null ||
        !completion.isFailure ||
        entry.initiatorReleased ||
        entry.appClaim != null) {
      return null;
    }

    return entry.initiatorClaim ??= GraphInitiatorPresentationClaim._(
      token,
      completion,
      entry,
    );
  }

  /// Завершает экранную сессию инициатора.
  ///
  /// Неподтверждённая ошибка становится доступной оболочке в своём прежнем
  /// порядке; прежний initiator claim больше не может её подтвердить.
  void releaseInitiatorPresentation(GraphOperationToken token) {
    final entry = _entries[token];
    if (entry == null || entry.initiatorReleased) {
      return;
    }

    _releaseInitiatorEntry(entry);
  }

  /// Освобождает право только пока [claim] остаётся действующим правом
  /// инициатора.
  ///
  /// Запоздалый renderer прежнего claim не может освободить право, уже
  /// переданное другому владельцу.
  void releaseInitiatorClaim(GraphInitiatorPresentationClaim claim) {
    final entry = _entries[claim.token];
    if (entry == null || !identical(entry.initiatorClaim, claim)) {
      return;
    }

    _releaseInitiatorEntry(entry);
  }

  void _releaseInitiatorEntry(_PresentationEntry entry) {
    entry.initiatorReleased = true;
    entry.initiatorClaim = null;
    _dispatchAppPresentation();
  }

  GraphAppPresentationRegistration registerAppPresentation() {
    final registration = GraphAppPresentationRegistration._(this);
    if (_shutdownCompleter?.isCompleted ?? false) {
      registration._isReleased = true;
    } else {
      _registrations.add(registration);
    }
    return registration;
  }

  /// Атомарно подтверждает фактическое предъявление действующим владельцем.
  ///
  /// Claim освобождённого или сменившегося владельца бездействует.
  void confirmPresentation(GraphInitiatorPresentationClaim claim) {
    final entry = _entries[claim.token];
    if (entry == null ||
        !identical(entry, claim._entry) ||
        !identical(entry.initiatorClaim, claim)) {
      return;
    }
    _discardEntry(entry);
  }

  /// Атомарно потребляет охваченные сообщением результаты действующего права.
  ///
  /// Остальные записи возвращаются в ожидание на прежних местах. Пустое или
  /// чужое подмножество вызывает [ArgumentError] без изменения права и записей.
  /// Подтверждение устаревшего права бездействует.
  void confirmAppPresentation(
    GraphAppPresentationClaim claim,
    Iterable<GraphOperationToken> covered,
  ) {
    final registration = claim._registration;
    if (!identical(registration._coordinator, this) ||
        !identical(registration._issued, claim)) {
      return;
    }
    final coveredTokens = covered.toSet();
    final claimTokens = claim.completions
        .map((completion) => completion.token)
        .toSet();
    if (coveredTokens.isEmpty || !claimTokens.containsAll(coveredTokens)) {
      throw ArgumentError.value(
        covered,
        'covered',
        'Ожидается непустое подмножество результатов права',
      );
    }

    for (final entry in claim._entries) {
      entry.appClaim = null;
      if (coveredTokens.contains(entry.token)) {
        _discardEntry(entry);
      }
    }
    registration._issued = null;
    _dispatchAppPresentation();
  }

  Future<void> shutdown() {
    final existing = _shutdownCompleter;
    if (existing != null) {
      return existing.future;
    }

    _isDraining = true;
    final shutdown = Completer<void>();
    _shutdownCompleter = shutdown;
    _completeShutdownIfDrained();
    return shutdown.future;
  }

  Future<GraphAppPresentationClaim?> _requestAppClaim(
    GraphAppPresentationRegistration registration,
  ) {
    if (registration._isReleased) {
      return Future.value(null);
    }
    final existing = registration._request;
    if (existing != null) {
      return existing.future;
    }

    final request = Completer<GraphAppPresentationClaim?>();
    registration._request = request;
    _dispatchAppPresentation();
    return request.future;
  }

  void _releaseRegistration(GraphAppPresentationRegistration registration) {
    if (registration._isReleased) {
      return;
    }
    registration._isReleased = true;
    _registrations.remove(registration);

    final issued = registration._issued;
    registration._issued = null;
    if (issued != null) {
      for (final entry in issued._entries) {
        entry.appClaim = null;
      }
    }
    final request = registration._request;
    registration._request = null;
    if (request != null && !request.isCompleted) {
      request.complete(null);
    }
    _dispatchAppPresentation();
  }

  void _dispatchAppPresentation() {
    if (_registrations.isEmpty) {
      return;
    }
    final active = _registrations.first;
    final request = active._request;
    if (request == null || active._issued != null) {
      return;
    }
    final entries = _appPresentableEntries().toList(growable: false);
    if (entries.isEmpty) {
      return;
    }

    final claim = GraphAppPresentationClaim._(entries, active);
    for (final entry in entries) {
      entry.appClaim = claim;
    }
    active._issued = claim;
    active._request = null;
    request.complete(claim);
  }

  Iterable<_PresentationEntry> _appPresentableEntries() sync* {
    for (final entry in _entries.values) {
      final completion = entry.completion;
      if (completion == null || entry.appClaim != null) {
        continue;
      }
      final belongsToApp = !completion.isFailure || entry.initiatorReleased;
      if (belongsToApp) {
        yield entry;
      }
    }
  }

  Future<Result<ConfirmedGraphResult<IntentionCommandSuccess>>>
  _executeIntention(IntentionCommand command) async {
    try {
      return await _repository.execute(command);
    } on Object {
      return const ResultFailure<ConfirmedGraphResult<IntentionCommandSuccess>>(
        IntentionUnexpectedFailure(),
      );
    }
  }

  Future<LongTermRelationCommandResult> _executeLongTermRelation(
    LongTermRelationCommand command,
  ) async {
    try {
      return await _repository.execute(command);
    } on Object {
      return const GraphCommandFailed<
        LongTermRelationCommandSuccess,
        LongTermRelationCommandFailure
      >(LongTermRelationUnexpectedFailure());
    }
  }

  Future<DailyChoiceCommandResult> _executeDailyChoice(
    DailyChoiceCommand command,
  ) async {
    try {
      return await _repository.execute(command);
    } on Object {
      return const GraphCommandFailed<
        DailyChoiceCommandSuccess,
        DailyChoiceCommandFailure
      >(DailyChoiceUnexpectedFailure());
    }
  }

  Future<TagCommandResult> _executeTag(TagCommand command) async {
    try {
      return await _repository.execute(command);
    } on Object {
      return const TagCommandFailed(TagUnexpectedFailure());
    }
  }

  void _discardEntry(_PresentationEntry entry) {
    if (identical(_entries[entry.token], entry)) {
      _entries.remove(entry.token);
    }
  }

  void _completeShutdownIfDrained() {
    final shutdown = _shutdownCompleter;
    if (shutdown == null || shutdown.isCompleted || _inFlight.isNotEmpty) {
      return;
    }

    _entries.clear();
    for (final registration in _registrations.toList(growable: false)) {
      registration._isReleased = true;
      registration._issued = null;
      final request = registration._request;
      registration._request = null;
      if (request != null && !request.isCompleted) {
        request.complete(null);
      }
    }
    _registrations.clear();
    _gates.clear();
    unawaited(_completionController.close());
    shutdown.complete();
  }
}

final class _PresentationEntry {
  _PresentationEntry(this.token);

  final GraphOperationToken token;
  GraphPresentableCompletion? completion;
  bool initiatorReleased = false;
  GraphInitiatorPresentationClaim? initiatorClaim;
  GraphAppPresentationClaim? appClaim;
}

sealed class _GraphCommandAcceptance {
  const _GraphCommandAcceptance();
}

final class _GraphCommandAccepted extends _GraphCommandAcceptance {
  const _GraphCommandAccepted(this.future);

  final Future<GraphCommandCompletion> future;
}

final class _GraphCommandAlreadyRunning extends _GraphCommandAcceptance {
  const _GraphCommandAlreadyRunning();
}

final class _GraphCommandDraining extends _GraphCommandAcceptance {
  const _GraphCommandDraining();
}

IntentionCommandKind _kindOf(IntentionCommand command) => switch (command) {
  CreateIntention() => IntentionCommandKind.create,
  UpdateIntention() => IntentionCommandKind.update,
  EnableIntentionReadiness() => IntentionCommandKind.enableReadiness,
  DisableIntentionReadiness() => IntentionCommandKind.disableReadiness,
  ArchiveIntention() => IntentionCommandKind.archive,
  RestoreIntention() => IntentionCommandKind.restore,
  DeleteIntention() => IntentionCommandKind.delete,
};
