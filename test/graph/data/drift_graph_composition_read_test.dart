import 'dart:async';

import 'package:doable/src/daily_choice/application/confirmed_choice_path.dart';
import 'package:doable/src/daily_choice/application/daily_choice_command.dart';
import 'package:doable/src/daily_choice/application/daily_choice_result.dart';
import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:doable/src/daily_choice/domain/daily_choice.dart';
import 'package:doable/src/data/local/app_database.dart'
    show
        LocalDatabaseConnectionObserver,
        LocalDatabaseSqlOperation,
        LocalDatabaseSqlStatement;
import 'package:doable/src/data_transfer/application/graph_composition.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_command.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/shared/diagnostics/diagnostics_sink.dart';
import 'package:doable/src/tag/application/tag_command.dart';
import 'package:doable/src/tag/application/tag_result.dart';
import 'package:doable/src/tag/domain/tag.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../support/in_memory_diagnostics_sink.dart';
import '../../support/local_database_harness.dart';

void main() {
  late LocalDatabaseHarness harness;
  late _ReadFailureProbe probe;
  late InMemoryDiagnosticsSink diagnostics;
  late DriftPersonalGraphRepository repository;

  setUp(() async {
    harness = LocalDatabaseHarness.inMemory();
    probe = _ReadFailureProbe();
    final database = await harness.openReadyDatabase(observer: probe);
    diagnostics = InMemoryDiagnosticsSink();
    var now = DateTime.utc(2026, 10, 18, 9);
    repository = DriftPersonalGraphRepository(
      database,
      UuidV7IntentionIdGenerator(),
      () => now = now.add(const Duration(seconds: 1)),
      diagnostics,
    );
  });

  tearDown(() => harness.dispose());

  Future<T> confirm<T extends GraphCommandOutcome>(
    GraphCommand<GraphCommandOutcome, GraphCommandFailure> command,
  ) async {
    final result = await repository.execute(command);
    expect(result, isA<GraphResultSuccess<Object?, GraphCommandFailure>>());
    final confirmed =
        (result as GraphResultSuccess<Object?, GraphCommandFailure>).value!
            as ConfirmedGraphResult;
    return confirmed.value as T;
  }

  Future<Tag> createTag(String name) async => (await confirm<TagCreated>(
    CreateTag(
      name: TagName.fromInput(name),
      color: null,
      placement: TagPlacement.first,
    ),
  )).tag;

  Future<Intention> createIntention(
    String title, {
    IntentionReadiness readiness = IntentionReadiness.notReady,
  }) async => (await confirm<IntentionSaved>(
    CreateIntention.withInitialState(
      title: title,
      description: null,
      readiness: readiness,
      tagIds: const {},
    ),
  )).intention;

  Future<LongTermRelation> relate(
    Intention source,
    Intention related, {
    LongTermRelationType type = LongTermRelationType.need,
  }) async => (await confirm<LongTermRelationCreated>(
    CreateLongTermRelation(
      sourceIntentionId: source.id,
      relatedIntentionId: related.id,
      type: type,
      priority: RelationPriority.p2,
      description: null,
    ),
  )).relation;

  Future<DailyChoice> choose(LongTermRelation relation) async =>
      (await confirm<DailyChoiceCreated>(
        CreateDailyChoice(
          sourceIntentionId: relation.sourceIntentionId,
          selectedIntentionId: relation.relatedIntentionId,
          path: ConfirmedChoicePath([
            ConfirmedChoicePathStep(
              relationId: relation.id,
              sourceIntentionId: relation.sourceIntentionId,
              type: relation.type,
              relatedIntentionId: relation.relatedIntentionId,
            ),
          ]),
          date: CalendarDate.fromParts(2026, 10, 18),
          description: null,
          isCompleted: false,
        ),
      )).choice;

  Future<GraphComposition> currentComposition() async {
    final read = await repository.watchComposition().first;
    return (read as GraphCompositionReadSucceeded).composition;
  }

  test('пустой граф новой установки пуст, и все числа его состава '
      'нулевые', () async {
    final composition = await currentComposition();

    expect(composition, _composition(0, 0, 0, 0));
    expect(composition.isEmpty, isTrue);
  });

  test('граф только с тегом не пуст', () async {
    await createTag('Дом');

    final composition = await currentComposition();

    expect(composition, _composition(0, 0, 0, 1));
    expect(composition.isEmpty, isFalse);
  });

  test('числа состава включают архивированные намерения и долговременные '
      'связи и дневные выборы', () async {
    final health = await createIntention('Здоровье');
    final running = await createIntention(
      'Бегать',
      readiness: IntentionReadiness.ready,
    );
    final swimming = await createIntention('Плавать');
    final needRunning = await relate(health, running);
    await relate(swimming, health, type: LongTermRelationType.can);
    await choose(needRunning);
    await confirm(ArchiveIntention(swimming.id));
    await confirm(ArchiveLongTermRelation(needRunning.id));

    final composition = await currentComposition();

    expect(composition, _composition(3, 2, 1, 0));
    expect(composition.isEmpty, isFalse);
  });

  test('наблюдение выдаёт новый состав после создания и удаления сущностей '
      'каждого вида и не повторяет состав после изменения, которое его не '
      'меняет', () async {
    final reads = StreamIterator(repository.watchComposition());
    addTearDown(reads.cancel);
    Future<GraphComposition> next() async {
      expect(await reads.moveNext(), isTrue);
      return (reads.current as GraphCompositionReadSucceeded).composition;
    }

    expect(await next(), _composition(0, 0, 0, 0));
    final home = await createTag('Дом');
    expect(await next(), _composition(0, 0, 0, 1));
    final health = await createIntention('Здоровье');
    expect(await next(), _composition(1, 0, 0, 1));
    final running = await createIntention(
      'Бегать',
      readiness: IntentionReadiness.ready,
    );
    expect(await next(), _composition(2, 0, 0, 1));
    final needRunning = await relate(health, running);
    expect(await next(), _composition(2, 1, 0, 1));
    final choice = await choose(needRunning);
    expect(await next(), _composition(2, 1, 1, 1));

    await confirm(
      UpdateTag(
        tagId: home.id,
        name: TagName.fromInput('Семья'),
        color: home.color,
      ),
    );
    await confirm(DeleteDailyChoice(choice.id));
    expect(await next(), _composition(2, 1, 0, 1));
    await confirm(DeleteLongTermRelation(needRunning.id));
    expect(await next(), _composition(2, 0, 0, 1));
    await confirm(DeleteIntention(running.id));
    expect(await next(), _composition(1, 0, 0, 1));
    await confirm(DeleteTag(home.id));
    expect(await next(), _composition(1, 0, 0, 0));
  });

  test('отказ чтения состава из-за повреждения хранилища — отказ, а не '
      'пустой граф: наблюдение заканчивается им, а диагностика записывает '
      'категорию повреждения', () async {
    probe.failure = sqlite.SqliteException(
      message: 'Повреждение',
      extendedResultCode: 11,
    );

    final reads = await repository.watchComposition().toList();

    expect(reads, [isA<GraphCompositionReadFailed>()]);
    expect(
      diagnostics.events.whereType<GraphCompositionReadDiagnosticsEvent>().map(
        (event) => event.status,
      ),
      [
        isA<DiagnosticsFailed>().having(
          (status) => status.code,
          'категория',
          DiagnosticsFailureCode.corruption,
        ),
      ],
    );
  });
}

GraphComposition _composition(
  int intentions,
  int relations,
  int dailyChoices,
  int tags,
) => GraphComposition(
  intentionCount: intentions,
  relationCount: relations,
  dailyChoiceCount: dailyChoices,
  tagCount: tags,
);

/// Отказывает каждое чтение базы, пока задан [failure].
final class _ReadFailureProbe extends LocalDatabaseConnectionObserver {
  Object? failure;

  @override
  void beforeStatement(LocalDatabaseSqlStatement statement) {
    if (statement.operation == LocalDatabaseSqlOperation.select) {
      if (failure case final error?) throw error;
    }
  }
}
