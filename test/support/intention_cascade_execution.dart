import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/intention/application/cascade/intention_cascade.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_command.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';

// Команды архивирования, удаления и восстановления с выполнением каскада.
//
// С настоящим хранилищем выполнение берётся из предпросмотра, как его берёт
// приложение при запуске операции: вариант «со вспомогательными» с его
// составом. Для отсутствующего предмета и неприменимой операции
// предпросмотра нет, а хранилище отклоняет такую команду до сверки состава,
// поэтому её создают с заданным составом, как и для подставного репозитория.

Future<ArchiveIntention> previewedArchiveIntention(
  IntentionCascadePreviewReadContract repository,
  IntentionId id,
) async => ArchiveIntention(
  id,
  execution: CascadeExecution.withSupporting(
    (await _preview<ArchiveCascadePreview>(
      repository,
      IntentionCascadeSubject(id),
      CascadeOperation.archive,
    )).plan,
  ),
);

Future<RestoreIntention> previewedRestoreIntention(
  IntentionCascadePreviewReadContract repository,
  IntentionId id,
) async => RestoreIntention(
  id,
  execution: CascadeExecution.withSupporting(
    (await _preview<RestoreCascadePreview>(
      repository,
      IntentionCascadeSubject(id),
      CascadeOperation.restore,
    )).plan,
  ),
);

Future<DeleteIntention> previewedDeleteIntention(
  IntentionCascadePreviewReadContract repository,
  IntentionId id,
) async => DeleteIntention(
  id,
  execution: CascadeExecution.withSupporting(
    (await _preview<IntentionDeleteCascadePreview>(
      repository,
      IntentionCascadeSubject(id),
      CascadeOperation.delete,
    )).plan,
  ),
);

Future<ArchiveLongTermRelation> previewedArchiveRelation(
  IntentionCascadePreviewReadContract repository,
  LongTermRelationId id,
) async => ArchiveLongTermRelation(
  id,
  execution: CascadeExecution.withSupporting(
    (await _preview<ArchiveCascadePreview>(
      repository,
      RelationCascadeSubject(id),
      CascadeOperation.archive,
    )).plan,
  ),
);

Future<RestoreLongTermRelation> previewedRestoreRelation(
  IntentionCascadePreviewReadContract repository,
  LongTermRelationId id,
) async => RestoreLongTermRelation(
  id,
  execution: CascadeExecution.withSupporting(
    (await _preview<RestoreCascadePreview>(
      repository,
      RelationCascadeSubject(id),
      CascadeOperation.restore,
    )).plan,
  ),
);

Future<DeleteLongTermRelation> previewedDeleteRelation(
  IntentionCascadePreviewReadContract repository,
  LongTermRelationId id,
) async => DeleteLongTermRelation(
  id,
  execution: CascadeExecution.withSupporting(
    (await _preview<RelationDeleteCascadePreview>(
      repository,
      RelationCascadeSubject(id),
      CascadeOperation.delete,
    )).plan,
  ),
);

Future<P> _preview<P extends CascadePreview>(
  IntentionCascadePreviewReadContract repository,
  CascadeSubject subject,
  CascadeOperation operation,
) async {
  final preview = await repository.previewCurrentCascade(subject, operation);
  if (preview is! P) {
    throw StateError(
      'Предпросмотр $operation не прочитан: ${preview.runtimeType}. '
      'Команде без предпросмотра нужен заданный состав.',
    );
  }
  return preview;
}

ArchiveIntention givenArchiveIntention(IntentionId id) =>
    ArchiveIntention(id, execution: _execution(_emptyArchiveComposition()));

RestoreIntention givenRestoreIntention(IntentionId id) =>
    RestoreIntention(id, execution: _execution(_emptyRestoreComposition()));

DeleteIntention givenDeleteIntention(IntentionId id) =>
    DeleteIntention(id, execution: _execution(_emptyDeleteComposition()));

ArchiveLongTermRelation givenArchiveRelation(LongTermRelationId id) =>
    ArchiveLongTermRelation(
      id,
      execution: _execution(_emptyArchiveComposition()),
    );

RestoreLongTermRelation givenRestoreRelation(LongTermRelationId id) =>
    RestoreLongTermRelation(
      id,
      execution: _execution(_emptyRestoreComposition()),
    );

DeleteLongTermRelation givenDeleteRelation(LongTermRelationId id) =>
    DeleteLongTermRelation(
      id,
      execution: _execution(_emptyDeleteComposition()),
    );

CascadeExecution<C> _execution<C extends CascadeComposition>(C expected) =>
    CascadeExecution.of(_plan(expected), CascadeChoice.withSupporting);

/// Состав операции, которая не затрагивает другие намерения.
ArchiveCascadeComposition _emptyArchiveComposition() =>
    ArchiveCascadeComposition(
      departing: const [],
      promoted: const [],

      archivedRelationCount: 0,
    );

RestoreCascadeComposition _emptyRestoreComposition() =>
    RestoreCascadeComposition(
      restored: const [],
      returnedAsMain: null,
      restoredRelationCount: 0,
    );

DeleteCascadeComposition _emptyDeleteComposition() => DeleteCascadeComposition(
  departing: const [],
  promoted: const [],
  archivedByInvariant: const [],
  mainsLosingRelation: const [],
  deletedRelationCount: 0,
);

/// Предпросмотр подставного репозитория: [operation] над [subject] не
/// затрагивает другие намерения.
CascadePreview givenCascadePreview(
  CascadeSubject subject,
  CascadeOperation operation,
  GraphRevision revision,
) => switch ((subject, operation)) {
  (_, CascadeOperation.archive) => ArchiveCascadePreview(
    revision: revision,
    plan: _plan(_emptyArchiveComposition()),
    titles: const {},
  ),
  (_, CascadeOperation.restore) => RestoreCascadePreview(
    revision: revision,
    plan: _plan(_emptyRestoreComposition()),
    titles: const {},
  ),
  (IntentionCascadeSubject(), CascadeOperation.delete) =>
    IntentionDeleteCascadePreview(
      revision: revision,
      plan: _plan(_emptyDeleteComposition()),
      titles: const {},
      isInActionPath: false,
    ),
  (RelationCascadeSubject(), CascadeOperation.delete) =>
    RelationDeleteCascadePreview(
      revision: revision,
      plan: _plan(_emptyDeleteComposition()),
      titles: const {},
    ),
};

CascadePlan<C> _plan<C extends CascadeComposition>(C composition) =>
    CascadePlan(
      withSupporting: composition,
      onlyThis: composition,
      asksQuestion: false,
    );
