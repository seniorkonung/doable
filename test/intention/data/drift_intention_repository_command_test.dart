import 'package:doable/src/data/local/app_database.dart'
    hide Intention, TagAssignment;
import 'package:doable/src/favorite/application/favorite_intentions.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_details.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/intention/domain/intention_text.dart';
import 'package:doable/src/shared/diagnostics/developer_diagnostics_sink.dart';
import 'package:doable/src/shared/diagnostics/diagnostics_sink.dart';
import 'package:doable/src/tag/application/tag_assignments.dart';
import 'package:doable/src/tag/application/tag_change.dart';
import 'package:doable/src/tag/application/tag_command.dart';
import 'package:doable/src/tag/application/tag_result.dart';
import 'package:doable/src/tag/domain/tag_assignment.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import '../../support/favorite_storage_fixture.dart';
import '../../support/in_memory_diagnostics_sink.dart';
import '../../support/tag_storage_fixture.dart';

void main() {
  late AppDatabase database;
  late InMemoryDiagnosticsSink diagnostics;
  late _DeterministicIntentionIdGenerator idGenerator;
  late _DeterministicClock clock;
  late DriftPersonalGraphRepository repository;
  late _WriteTrace writeTrace;
  late Database raw;

  setUp(() async {
    writeTrace = _WriteTrace();
    database = AppDatabase(
      observeConfiguredLocalDatabaseConnection(
        openInMemoryLocalDatabase(setup: (connection) => raw = connection),
        writeTrace,
      ),
    );
    await database.open();
    diagnostics = InMemoryDiagnosticsSink();
    idGenerator = _DeterministicIntentionIdGenerator([_id(_firstUuid)]);
    clock = _DeterministicClock([DateTime.utc(2026, 9, 3, 12)]);
    repository = DriftPersonalGraphRepository(
      database,
      idGenerator,
      clock.call,
      diagnostics,
    );
  });

  tearDown(() => database.close());

  group('DriftPersonalGraphRepository.execute', () {
    group('Собственные теги каталожных снимков команд', () {
      late IntentionId id;
      late List<String> expectedTagNames;

      setUp(() {
        seedTagStorageFixture(raw);
        id = _id(tagFixtureId(1));
        expectedTagNames = ['Дом'];
        for (var index = 0; index < 105; index++) {
          final name = 'Собственный тег $index';
          expectedTagNames.add(name);
          raw.execute('INSERT INTO tags (id, name) VALUES (?, ?)', [
            tagFixtureId(2000 - index),
            name,
          ]);
        }
        for (var index = 104; index >= 0; index--) {
          raw.execute(
            'INSERT INTO tag_assignments (tag_id, intention_id) VALUES (?, ?)',
            [tagFixtureId(2000 - index), id.toCanonicalString()],
          );
        }
      });

      test(
        'снимки изменения полей сохраняют полные собственные теги',
        () async {
          writeTrace.overrideNextSelect(const {
            'title_search_key': 'историческая проекция',
          });
          final saved = _commandSuccess(
            await repository.execute(
              UpdateIntention(
                id: id,
                title: 'Новое название',
                description: null,
              ),
            ),
          ) as IntentionSaved;
          final mutation = saved.catalogMutation as IntentionCatalogUpdated;

          expect(mutation.before.summary.title, 'Намерение 1');
          expect(mutation.after.summary.title, 'Новое название');
          IntentionCatalogQuery query(String titleFilter) =>
              IntentionCatalogQuery(
                scope: IntentionScope.all,
                titleFilter: titleFilter,
                order: IntentionCatalogOrder.createdAtDescending,
                pageSize: 1,
              );
          expect(mutation.before.matches(query('историческая')), isTrue);
          expect(mutation.before.matches(query('Намерение 1')), isFalse);
          expect(mutation.after.matches(query('историческая')), isFalse);
          expect(mutation.after.matches(query('Новое название')), isTrue);
          for (final entry in [mutation.before, mutation.after]) {
            expect(entry.summary.id, id);
            expect(
              entry.summary.tags.map((tag) => tag.name.value),
              expectedTagNames,
            );
            expect(
              entry.summary.tags.first.id.toCanonicalString(),
              tagFixtureId(firstTagNumber),
            );
            expect(entry.summary.activeRelationCount, 1);
            expect(() => entry.summary.tags.clear(), throwsUnsupportedError);
          }
        },
      );

      for (final (name, command, isReady, isArchived)
          in <(String, IntentionCommand Function(IntentionId), int, int)>[
            ('включения готовности', EnableIntentionReadiness.new, 0, 0),
            ('выключения готовности', DisableIntentionReadiness.new, 1, 0),
            ('архивирования', ArchiveIntention.new, 1, 0),
            ('восстановления из архива', RestoreIntention.new, 1, 1),
          ]) {
        test('снимки $name сохраняют полные собственные теги', () async {
          if (isArchived == 1) {
            raw.execute('UPDATE long_term_relations SET is_archived = 1');
          }
          raw.execute(
            'UPDATE intentions SET is_action_ready = ?, is_archived = ? WHERE id = ?',
            [isReady, isArchived, id.toCanonicalString()],
          );
          final saved = _commandSuccess(
            await repository.execute(command(id)),
          ) as IntentionSaved;
          final mutation = saved.catalogMutation as IntentionCatalogUpdated;

          for (final entry in [mutation.before, mutation.after]) {
            expect(entry.summary.id, id);
            expect(entry.summary.title, 'Намерение 1');
            expect(entry.summary.hasDescription, isTrue);
            expect(
              entry.summary.tags.map((tag) => tag.name.value),
              expectedTagNames,
            );
          }
          expect(
            mutation.before.summary.readiness,
            isReady == 1
                ? IntentionReadiness.ready
                : IntentionReadiness.notReady,
          );
          expect(
            mutation.before.summary.archiveState,
            isArchived == 1
                ? IntentionArchiveState.archived
                : IntentionArchiveState.active,
          );
          expect(mutation.after.summary.readiness, saved.intention.readiness);
          expect(
            mutation.after.summary.archiveState,
            saved.intention.archiveState,
          );
          expect(
            mutation.before.summary.createdAt.value.microsecondsSinceEpoch,
            101,
          );
          expect(
            mutation.before.summary.updatedAt.value.microsecondsSinceEpoch,
            201,
          );
          expect(
            mutation.after.summary.createdAt,
            mutation.before.summary.createdAt,
          );
          expect(mutation.after.summary.updatedAt, saved.intention.updatedAt);
          expect(
            mutation.before.summary.activeRelationCount,
            isArchived == 1 ? 0 : 1,
          );
          expect(
            mutation.after.summary.activeRelationCount,
            command(id) is ArchiveIntention || isArchived == 1 ? 0 : 1,
          );
        });
      }

      for (final (name, command, isReady, isArchived)
          in <(String, IntentionCommand Function(IntentionId), int, int)>[
            (
              'изменения полей',
              (id) => UpdateIntention(
                id: id,
                title: 'Намерение 1',
                description: 'Описание 1',
              ),
              1,
              0,
            ),
            ('включения готовности', EnableIntentionReadiness.new, 1, 0),
            ('выключения готовности', DisableIntentionReadiness.new, 0, 0),
            ('архивирования', ArchiveIntention.new, 1, 1),
            ('восстановления из архива', RestoreIntention.new, 1, 0),
          ]) {
        test('повтор $name сохраняет проверенные теги без записи', () async {
          if (isArchived == 1) {
            raw.execute('UPDATE long_term_relations SET is_archived = 1');
          }
          raw.execute(
            'UPDATE intentions SET is_action_ready = ?, is_archived = ? WHERE id = ?',
            [isReady, isArchived, id.toCanonicalString()],
          );
          writeTrace.updateStatements.clear();

          final saved = _commandSuccess(
            await repository.execute(command(id)),
          ) as IntentionSaved;
          final mutation = saved.catalogMutation as IntentionCatalogUnchanged;

          expect(mutation.before, same(mutation.after));
          expect(
            mutation.entry.summary.tags.map((tag) => tag.name.value),
            expectedTagNames,
          );
          expect(clock.calls, 0);
          expect(writeTrace.updateStatements, isEmpty);
        });
      }

      test(
        'каждая сторона снимка читает назначения на своём состоянии транзакции',
        () async {
          raw.execute('''CREATE TRIGGER change_own_tags_after_update
          AFTER UPDATE ON intentions WHEN NEW.id = '${id.toCanonicalString()}'
          BEGIN
            DELETE FROM tag_assignments
              WHERE intention_id = NEW.id AND tag_id = '${tagFixtureId(firstTagNumber)}';
            INSERT INTO tag_assignments (tag_id, intention_id)
              VALUES ('${tagFixtureId(lastTagNumber)}', NEW.id);
          END''');

          final saved = _commandSuccess(
            await repository.execute(
              UpdateIntention(
                id: id,
                title: 'Новое название',
                description: null,
              ),
            ),
          ) as IntentionSaved;
          final mutation = saved.catalogMutation as IntentionCatalogUpdated;

          expect(
            mutation.before.summary.tags.map((tag) => tag.name.value),
            expectedTagNames,
          );
          expect(mutation.after.summary.tags.map((tag) => tag.name.value), [
            'Работа',
            ...expectedTagNames.skip(1),
          ]);
          expect(
            mutation.before.summary.tags.first.id.toCanonicalString(),
            tagFixtureId(firstTagNumber),
          );
          expect(
            mutation.after.summary.tags.first.id.toCanonicalString(),
            tagFixtureId(lastTagNumber),
          );
        },
      );

      test(
        'снимок удаления сохраняет теги до каскадного удаления назначений',
        () async {
          raw.execute('DELETE FROM daily_choices');
          raw.execute('DELETE FROM long_term_relations');

          final deleted = _commandSuccess(
            await repository.execute(DeleteIntention(id)),
          ) as IntentionDeleted;
          final mutation = deleted.catalogMutation as IntentionCatalogDeleted;

          expect(mutation.before.summary.id, id);
          expect(
            mutation.before.summary.tags.map((tag) => tag.name.value),
            expectedTagNames,
          );
          expect(mutation.after, isNull);
          expect(
            raw.select('SELECT * FROM tag_assignments WHERE intention_id = ?', [
              id.toCanonicalString(),
            ]),
            isEmpty,
          );
          expect(raw.select('SELECT * FROM tags'), hasLength(107));
          expect(
            raw.select('SELECT * FROM tag_assignments WHERE intention_id = ?', [
              tagFixtureId(3),
            ]),
            hasLength(1),
          );
        },
      );

      for (final (side, selectsToSkip, expectedClockCalls) in [
        ('до изменения', 2, 0),
        ('после изменения', 4, 1),
      ]) {
        test(
          'повреждение тегов $side отклоняет команду и сохраняет ревизию',
          () async {
            final query = IntentionCatalogQuery(
              scope: IntentionScope.all,
              titleFilter: null,
              order: IntentionCatalogOrder.createdAtDescending,
              pageSize: 100,
            );
            final revisionBefore = _firstCatalogPage(
              await repository.getCatalogPage(query),
            ).revision;
            writeTrace.overrideSelectAfter(
              skippedNonEmptySelects: selectsToSkip,
              overrides: const {'assigned_tag_id': 'повреждённая ссылка'},
            );

            final result = await repository.execute(
              UpdateIntention(
                id: id,
                title: 'Новое название',
                description: null,
              ),
            );

            expect(result, _failure<IntentionCorruptionFailure>());
            expect(clock.calls, expectedClockCalls);
            final stored = raw.select(
              'SELECT title, description, updated_at FROM intentions WHERE id = ?',
              [id.toCanonicalString()],
            ).single;
            expect(stored['title'], 'Намерение 1');
            expect(stored['description'], 'Описание 1');
            expect(stored['updated_at'], 201);
            final pageAfter = _firstCatalogPage(
              await repository.getCatalogPage(query),
            );
            expect(
              revisionBefore.compareTo(pageAfter.revision),
              GraphRevisionOrder.same,
            );
            expect(
              pageAfter.items
                  .singleWhere((item) => item.id == id)
                  .tags
                  .map((tag) => tag.name.value),
              expectedTagNames,
            );
          },
        );
      }

      group('Команды назначения тега', () {
        IntentionCatalogQuery requiring(int tagNumber) => IntentionCatalogQuery(
          scope: IntentionScope.all,
          titleFilter: null,
          tagFilter: IntentionTagFilter(
            requiredTagIds: [_tagId(tagFixtureId(tagNumber))],
          ),
          order: IntentionCatalogOrder.createdAtDescending,
          pageSize: 100,
        );
        final catalogQuery = IntentionCatalogQuery(
          scope: IntentionScope.all,
          titleFilter: null,
          order: IntentionCatalogOrder.createdAtDescending,
          pageSize: 100,
        );

        for (final (name, command, tagNumber, beforeNames, afterNames)
            in <
              (
                String,
                TagCommand Function(TagId, IntentionId),
                int,
                List<String> Function(List<String>),
                List<String> Function(List<String>),
              )
            >[
              (
                'назначение',
                (tagId, intentionId) =>
                    AssignTag(tagId: tagId, intentionId: intentionId),
                lastTagNumber,
                (names) => names,
                (names) => [names.first, 'Работа', ...names.skip(1)],
              ),
              (
                'снятие',
                (tagId, intentionId) =>
                    RemoveTagAssignment(tagId: tagId, intentionId: intentionId),
                firstTagNumber,
                (names) => names,
                (names) => names.skip(1).toList(),
              ),
            ]) {
          test(
            '$name добавляет полные снимки намерения в пакет той же ревизии',
            () async {
              final revisionBefore = _firstCatalogPage(
                await repository.getCatalogPage(catalogQuery),
              ).revision;
              final tagId = _tagId(tagFixtureId(tagNumber));

              final confirmed = _tagCommandSuccess(
                await repository.execute(command(tagId, id)),
              );
              final changed = confirmed.value as TagAssignmentChanged;
              final mutation = changed.catalogMutation;

              expect(
                confirmed.revision.compareTo(revisionBefore),
                GraphRevisionOrder.newer,
              );
              expect(confirmed.changes, [same(changed.change), same(mutation)]);
              expect(
                confirmed.changes.whereType<IntentionCatalogMutation>(),
                hasLength(1),
              );
              expect(
                mutation.before.summary.tags.map((tag) => tag.name.value),
                beforeNames(expectedTagNames),
              );
              expect(
                mutation.after.summary.tags.map((tag) => tag.name.value),
                afterNames(expectedTagNames),
              );
              final assigned = changed.state == TagAssignmentState.assigned;
              expect(mutation.before.matches(requiring(tagNumber)), !assigned);
              expect(mutation.after.matches(requiring(tagNumber)), assigned);
              for (final entry in [mutation.before, mutation.after]) {
                expect(entry.summary.id, id);
                expect(entry.summary.title, 'Намерение 1');
                expect(entry.summary.activeRelationCount, 1);
                expect(
                  entry.summary.createdAt.value.microsecondsSinceEpoch,
                  101,
                );
                expect(
                  entry.summary.updatedAt.value.microsecondsSinceEpoch,
                  201,
                );
              }
              expect(clock.calls, 0);
              expect(
                raw
                    .select(
                      'SELECT created_at, updated_at FROM intentions WHERE id = ?',
                      [id.toCanonicalString()],
                    )
                    .single
                    .values,
                [101, 201],
              );
              final pageAfter = _firstCatalogPage(
                await repository.getCatalogPage(catalogQuery),
              );
              expect(
                pageAfter.revision.compareTo(confirmed.revision),
                GraphRevisionOrder.same,
              );
              expect(
                pageAfter.items
                    .singleWhere((item) => item.id == id)
                    .tags
                    .map((tag) => tag.name.value),
                afterNames(expectedTagNames),
              );
            },
          );
        }

        for (final (name, command) in <(String, TagCommand)>[
          (
            'назначения',
            AssignTag(
              tagId: _tagId(tagFixtureId(firstTagNumber)),
              intentionId: _id(tagFixtureId(1)),
            ),
          ),
          (
            'снятия',
            RemoveTagAssignment(
              tagId: _tagId(tagFixtureId(lastTagNumber)),
              intentionId: _id(tagFixtureId(1)),
            ),
          ),
        ]) {
          test('повтор $name не даёт мутации и новой ревизии', () async {
            final revisionBefore = _firstCatalogPage(
              await repository.getCatalogPage(catalogQuery),
            ).revision;

            final confirmed = _tagCommandSuccess(
              await repository.execute(command),
            );

            expect(confirmed.value, isA<TagAssignmentUnchanged>());
            expect(confirmed.changes, [isA<TagAssignmentUnchangedChange>()]);
            expect(
              confirmed.revision.compareTo(revisionBefore),
              GraphRevisionOrder.same,
            );
          });
        }

        for (final (side, skippedTagReads, stage) in [
          ('до', 0, TagCommandDiagnosticsStage.validation),
          ('после', 1, TagCommandDiagnosticsStage.resultRead),
        ]) {
          test(
            'повреждение тегов снимка $side записи отклоняет команду без пакета',
            () async {
              final revisionBefore = _firstCatalogPage(
                await repository.getCatalogPage(catalogQuery),
              ).revision;
              writeTrace.overrideSelectWithColumn(
                'assigned_tag_id',
                skippedMatchingSelects: skippedTagReads,
                overrides: const {'assigned_tag_id': 'повреждённая ссылка'},
              );

              final result = await repository.execute(
                AssignTag(
                  tagId: _tagId(tagFixtureId(lastTagNumber)),
                  intentionId: id,
                ),
              );

              expect(
                result,
                isA<TagCommandFailed>().having(
                  (result) => result.failure,
                  'failure',
                  isA<TagCorruptionFailure>(),
                ),
              );
              expect(
                diagnostics.events.whereType<TagCommandDiagnosticsEvent>().last,
                isA<TagCommandDiagnosticsEvent>()
                    .having((event) => event.stage, 'stage', stage)
                    .having(
                      (event) => event.status,
                      'status',
                      isA<DiagnosticsFailed>(),
                    ),
              );
              expect(
                raw.select(
                  'SELECT 1 FROM tag_assignments WHERE tag_id = ? AND intention_id = ?',
                  [tagFixtureId(lastTagNumber), id.toCanonicalString()],
                ),
                isEmpty,
              );
              final pageAfter = _firstCatalogPage(
                await repository.getCatalogPage(catalogQuery),
              );
              expect(
                pageAfter.revision.compareTo(revisionBefore),
                GraphRevisionOrder.same,
              );
              expect(clock.calls, 0);
            },
          );
        }
      });
    });

    test('создаёт active not-ready намерение с нормализованными данными и единым UTC-временем', () async {
      final result = await repository.execute(
        const CreateIntention(
          title: '  Купить  молоко  ',
          description: '  В фермерском магазине\n',
        ),
      );

      final saved = _saved(result);
      expect(saved.id, _id(_firstUuid));
      expect(saved.title, 'Купить  молоко');
      expect(saved.description, '  В фермерском магазине\n');
      expect(saved.readiness, IntentionReadiness.notReady);
      expect(saved.archiveState, IntentionArchiveState.active);
      expect(saved.createdAt.value, DateTime.utc(2026, 9, 3, 12));
      expect(saved.createdAt.value.isUtc, isTrue);
      expect(saved.updatedAt, saved.createdAt);
      expect(idGenerator.generated, [_id(_firstUuid)]);
      expect(clock.calls, 1);
      expect(diagnostics.events, [
        _successfulCommand(IntentionCommandDiagnosticsType.create),
      ]);
    });

    test('допускает два намерения с одинаковым названием и разными идентификаторами', () async {
      final secondId = _id(_secondUuid);
      idGenerator = _DeterministicIntentionIdGenerator([
        _id(_firstUuid),
        secondId,
      ]);
      clock = _DeterministicClock([
        DateTime.utc(2026, 9, 3, 12),
        DateTime.utc(2026, 9, 3, 13),
      ]);
      repository = DriftPersonalGraphRepository(
        database,
        idGenerator,
        clock.call,
        diagnostics,
      );

      final first = _saved(
        await repository.execute(
          const CreateIntention(title: 'Быть здоровым', description: null),
        ),
      );
      final second = _saved(
        await repository.execute(
          const CreateIntention(title: 'Быть здоровым', description: null),
        ),
      );

      expect(first.id, _id(_firstUuid));
      expect(second.id, secondId);
      expect(first.id, isNot(second.id));
      expect(await database.select(database.intentions).get(), hasLength(2));
    });

    test('публикует точные catalog mutations и меняет revision только после commit', () async {
      clock = _DeterministicClock([
        DateTime.utc(2026, 9, 3, 12),
        DateTime.utc(2026, 9, 3, 13),
      ]);
      repository = DriftPersonalGraphRepository(
        database,
        idGenerator,
        clock.call,
        diagnostics,
      );
      final milkQuery = IntentionCatalogQuery(
        scope: IntentionScope.active,
        titleFilter: 'молоко',
        order: IntentionCatalogOrder.createdAtDescending,
        pageSize: 100,
      );
      final doctorQuery = IntentionCatalogQuery(
        scope: IntentionScope.active,
        titleFilter: 'врачу',
        order: IntentionCatalogOrder.createdAtDescending,
        pageSize: 100,
      );
      final initialPage = _firstCatalogPage(
        await repository.getCatalogPage(milkQuery),
      );

      final created = _commandSuccess(
        await repository.execute(
          const CreateIntention(title: 'Купить молоко', description: null),
        ),
      ) as IntentionSaved;
      final createdMutation =
          created.catalogMutation as IntentionCatalogCreated;

      expect(
        initialPage.revision.compareTo(createdMutation.revision),
        GraphRevisionOrder.older,
      );
      expect(createdMutation.before, isNull);
      expect(createdMutation.after, same(createdMutation.entry));
      expect(createdMutation.entry.summary.id, created.intention.id);
      expect(createdMutation.entry.summary.tags, isEmpty);
      expect(createdMutation.entry.matches(milkQuery), isTrue);
      expect(createdMutation.entry.matches(doctorQuery), isFalse);

      final unchanged = _commandSuccess(
        await repository.execute(
          UpdateIntention(
            id: created.intention.id,
            title: created.intention.title,
            description: created.intention.description,
          ),
        ),
      ) as IntentionSaved;
      final unchangedMutation =
          unchanged.catalogMutation as IntentionCatalogUnchanged;

      expect(
        createdMutation.revision.compareTo(unchangedMutation.revision),
        GraphRevisionOrder.same,
      );
      expect(unchangedMutation.before, same(unchangedMutation.after));

      final updated = _commandSuccess(
        await repository.execute(
          UpdateIntention(
            id: created.intention.id,
            title: 'Позвонить врачу',
            description: null,
          ),
        ),
      ) as IntentionSaved;
      final updatedMutation =
          updated.catalogMutation as IntentionCatalogUpdated;

      expect(
        unchangedMutation.revision.compareTo(updatedMutation.revision),
        GraphRevisionOrder.older,
      );
      expect(updatedMutation.before.matches(milkQuery), isTrue);
      expect(updatedMutation.before.matches(doctorQuery), isFalse);
      expect(updatedMutation.after.matches(milkQuery), isFalse);
      expect(updatedMutation.after.matches(doctorQuery), isTrue);
      expect(updatedMutation.after.summary.title, 'Позвонить врачу');

      final deleted = _commandSuccess(
        await repository.execute(DeleteIntention(created.intention.id)),
      ) as IntentionDeleted;
      final deletedMutation =
          deleted.catalogMutation as IntentionCatalogDeleted;

      expect(
        updatedMutation.revision.compareTo(deletedMutation.revision),
        GraphRevisionOrder.older,
      );
      expect(deletedMutation.before, same(deletedMutation.entry));
      expect(deletedMutation.after, isNull);
      expect(deletedMutation.entry.matches(doctorQuery), isTrue);

      final failed = await repository.execute(
        DeleteIntention(created.intention.id),
      );
      expect(failed, _failure<IntentionNotFoundFailure>());
      final pageAfterFailure = _firstCatalogPage(
        await repository.getCatalogPage(doctorQuery),
      );
      expect(
        deletedMutation.revision.compareTo(pageAfterFailure.revision),
        GraphRevisionOrder.same,
      );
    });

    test(
      'отклоняет недопустимый Unicode title до генерации ID и записи',
      () async {
        final title = List.filled(256, '👩🏽‍💻').join();

        final result = await repository.execute(
          CreateIntention(title: title, description: null),
        );

        expect(result, _failure<IntentionValidationFailure>());
        expect(idGenerator.generated, isEmpty);
        expect(clock.calls, 0);
        expect(await database.select(database.intentions).get(), isEmpty);
        expect(diagnostics.events, [
          _failedCommand(
            IntentionCommandDiagnosticsType.create,
            DiagnosticsFailureCode.validation,
          ),
        ]);
      },
    );

    test('отклоняет недопустимый текст до SQL-чтения и записи', () async {
      final invalidValues = [
        '\u0000',
        String.fromCharCode(0xd800),
        String.fromCharCode(0xdc00),
      ];
      final invalidCommands = [
        for (final invalidValue in invalidValues) ...[
          (
            CreateIntention(title: 'Название$invalidValue', description: null),
            IntentionTextField.title,
          ),
          (
            CreateIntention(
              title: 'Название',
              description: 'Описание$invalidValue',
            ),
            IntentionTextField.description,
          ),
        ],
      ];

      for (final (command, field) in invalidCommands) {
        writeTrace.operations.clear();

        final result = await repository.execute(command);

        expect(
          result,
          _textValidationFailure(
            field: field,
            reason: IntentionTextValidationReason.invalidUnicodeRepertoire,
          ),
        );
        expect(writeTrace.operations, isEmpty);
        expect(idGenerator.generated, isEmpty);
        expect(clock.calls, 0);
      }

      expect(await database.select(database.intentions).get(), isEmpty);
      expect(
        diagnostics.events.whereType<IntentionCommandDiagnosticsEvent>(),
        everyElement(
          _failedCommand(
            IntentionCommandDiagnosticsType.create,
            DiagnosticsFailureCode.validation,
          ),
        ),
      );
    });

    test('не изменяет подтверждённое намерение при NUL в title', () async {
      final id = _id(_firstUuid);
      final createdAt = DateTime.utc(2026, 9, 2, 10);
      await _insertIntention(
        database,
        id: id.toCanonicalString(),
        title: 'Исходное название',
        description: 'Исходное описание',
        createdAt: createdAt,
      );
      writeTrace.operations.clear();

      final result = await repository.execute(
        UpdateIntention(
          id: id,
          title: 'Недопустимое\u0000название',
          description: 'Изменённое описание',
        ),
      );

      expect(
        result,
        _textValidationFailure(
          field: IntentionTextField.title,
          reason: IntentionTextValidationReason.invalidUnicodeRepertoire,
        ),
      );
      expect(writeTrace.operations, isEmpty);
      expect(clock.calls, 0);
      final row = await (database.select(
        database.intentions,
      )..where((row) => row.id.equals(id.toCanonicalString()))).getSingle();
      expect(row.title, 'Исходное название');
      expect(row.description, 'Исходное описание');
      expect(row.updatedAt, createdAt.microsecondsSinceEpoch);
    });

    test('принимает title из 255 Unicode-графем', () async {
      final title = List.filled(255, '👩🏽‍💻').join();

      final result = await repository.execute(
        CreateIntention(title: title, description: '  \n\t  '),
      );

      final saved = _saved(result);
      expect(saved.title, title);
      expect(saved.description, isNull);
    });

    test('возвращает conflict при collision нового первичного ключа и не перезаписывает строку', () async {
      await _insertIntention(
        database,
        id: _firstUuid,
        title: 'Существующее намерение',
        createdAt: DateTime.utc(2026, 9, 2, 10),
      );

      final result = await repository.execute(
        const CreateIntention(title: 'Новое намерение', description: null),
      );

      expect(result, _failure<IntentionConflictFailure>());
      final row = await (database.select(
        database.intentions,
      )..where((row) => row.id.equals(_firstUuid))).getSingle();
      expect(row.title, 'Существующее намерение');
      expect(
        row.createdAt,
        DateTime.utc(2026, 9, 2, 10).microsecondsSinceEpoch,
      );
      expect(diagnostics.events, [
        _failedCommand(
          IntentionCommandDiagnosticsType.create,
          DiagnosticsFailureCode.conflict,
        ),
      ]);
    });

    test('изменяет active и archived намерения, сохраняя их остальные подтверждённые данные', () async {
      final fixtures = [
        (
          id: _id(_firstUuid),
          isActionReady: false,
          isArchived: false,
          createdAt: DateTime.utc(2026, 9, 2, 10),
        ),
        (
          id: _id(_secondUuid),
          isActionReady: true,
          isArchived: true,
          createdAt: DateTime.utc(2026, 9, 2, 11),
        ),
      ];
      for (final fixture in fixtures) {
        await _insertIntention(
          database,
          id: fixture.id.toCanonicalString(),
          title: 'Исходное название',
          description: 'Исходное описание',
          isActionReady: fixture.isActionReady,
          isArchived: fixture.isArchived,
          createdAt: fixture.createdAt,
        );
      }

      clock = _DeterministicClock([
        DateTime.utc(2026, 9, 3, 12),
        DateTime.utc(2026, 9, 3, 13),
      ]);
      repository = DriftPersonalGraphRepository(
        database,
        idGenerator,
        clock.call,
        diagnostics,
      );

      for (var index = 0; index < fixtures.length; index++) {
        final fixture = fixtures[index];
        final result = await repository.execute(
          UpdateIntention(
            id: fixture.id,
            title: '  Обновлённое  название  ',
            description: '  Новое описание\n',
          ),
        );

        final saved = _saved(result);
        expect(saved.id, fixture.id);
        expect(saved.title, 'Обновлённое  название');
        expect(saved.description, '  Новое описание\n');
        expect(
          saved.readiness,
          fixture.isActionReady
              ? IntentionReadiness.ready
              : IntentionReadiness.notReady,
        );
        expect(
          saved.archiveState,
          fixture.isArchived
              ? IntentionArchiveState.archived
              : IntentionArchiveState.active,
        );
        expect(saved.createdAt.value, fixture.createdAt);
        expect(saved.updatedAt.value, DateTime.utc(2026, 9, 3, 12 + index));
      }

      final updatedRows = await database.select(database.intentions).get();
      expect(
        updatedRows.map((row) => row.titleSearchKey),
        everyElement('обновлённое  название'),
      );
      expect(diagnostics.events, [
        _successfulCommand(IntentionCommandDiagnosticsType.update),
        _successfulCommand(IntentionCommandDiagnosticsType.update),
      ]);
    });

    test(
      'не выполняет запись и возвращает прежнее намерение при no-op update',
      () async {
        final id = _id(_firstUuid);
        final createdAt = DateTime.utc(2026, 9, 2, 10);
        await _insertIntention(
          database,
          id: id.toCanonicalString(),
          title: 'Неизменное название',
          description: 'Неизменное описание',
          isActionReady: true,
          isArchived: true,
          createdAt: createdAt,
        );
        clock = _DeterministicClock([DateTime.utc(2026, 9, 3, 12)]);
        repository = DriftPersonalGraphRepository(
          database,
          idGenerator,
          clock.call,
          diagnostics,
        );
        writeTrace.updateStatements.clear();

        final result = await repository.execute(
          UpdateIntention(
            id: id,
            title: 'Неизменное название',
            description: 'Неизменное описание',
          ),
        );

        final saved = _saved(result);
        expect(saved.updatedAt.value, createdAt);
        expect(saved.createdAt.value, createdAt);
        expect(clock.calls, 0);
        expect(writeTrace.updateStatements, isEmpty);
      },
    );

    test(
      'сохраняет равные и убывающие показания часов для фактических изменений',
      () async {
        final id = _id(_firstUuid);
        final createdAt = DateTime.utc(2026, 9, 3, 12);
        final previouslyUpdatedAt = DateTime.utc(2026, 9, 3, 13);
        await _insertIntention(
          database,
          id: id.toCanonicalString(),
          title: 'Исходное название',
          createdAt: createdAt,
          updatedAt: previouslyUpdatedAt,
        );
        clock = _DeterministicClock([
          previouslyUpdatedAt,
          createdAt,
          DateTime.utc(2026, 9, 3, 11),
        ]);
        repository = DriftPersonalGraphRepository(
          database,
          idGenerator,
          clock.call,
          diagnostics,
        );
        writeTrace.updateStatements.clear();

        final titleUpdated = _saved(
          await repository.execute(
            UpdateIntention(
              id: id,
              title: 'Обновлённое название',
              description: null,
            ),
          ),
        );
        final readinessUpdated = _saved(
          await repository.execute(EnableIntentionReadiness(id)),
        );
        final archiveUpdated = _saved(
          await repository.execute(ArchiveIntention(id)),
        );

        expect(titleUpdated.updatedAt.value, previouslyUpdatedAt);
        expect(readinessUpdated.updatedAt.value, createdAt);
        expect(archiveUpdated.updatedAt.value, DateTime.utc(2026, 9, 3, 11));
        expect(archiveUpdated.createdAt.value, createdAt);
        expect(clock.calls, 3);
        expect(writeTrace.updateStatements, hasLength(3));
        final stored = await (database.select(
          database.intentions,
        )..where((row) => row.id.equals(id.toCanonicalString()))).getSingle();
        expect(
          stored.updatedAt,
          DateTime.utc(2026, 9, 3, 11).microsecondsSinceEpoch,
        );
      },
    );

    test('оставляет прежнее намерение при недопустимом изменении', () async {
      final id = _id(_firstUuid);
      final createdAt = DateTime.utc(2026, 9, 2, 10);
      await _insertIntention(
        database,
        id: id.toCanonicalString(),
        title: 'Исходное название',
        description: 'Исходное описание',
        createdAt: createdAt,
      );
      writeTrace.updateStatements.clear();

      final result = await repository.execute(
        UpdateIntention(id: id, title: '  \n\t  ', description: null),
      );

      expect(result, _failure<IntentionValidationFailure>());
      expect(clock.calls, 0);
      expect(writeTrace.updateStatements, isEmpty);
      final row = await (database.select(
        database.intentions,
      )..where((row) => row.id.equals(id.toCanonicalString()))).getSingle();
      expect(row.title, 'Исходное название');
      expect(row.description, 'Исходное описание');
      expect(row.updatedAt, createdAt.microsecondsSinceEpoch);
    });

    test(
      'возвращает not-found при изменении отсутствующего намерения',
      () async {
        final result = await repository.execute(
          UpdateIntention(
            id: _id(_firstUuid),
            title: 'Новое название',
            description: null,
          ),
        );

        expect(result, _failure<IntentionNotFoundFailure>());
        expect(clock.calls, 0);
        expect(diagnostics.events, [
          _failedCommand(
            IntentionCommandDiagnosticsType.update,
            DiagnosticsFailureCode.notFound,
          ),
        ]);
      },
    );

    test(
      'физически удаляет active и archived намерения из всех публичных чтений',
      () async {
        final fixtures = [
          (id: _id(_firstUuid), isArchived: false),
          (id: _id(_secondUuid), isArchived: true),
        ];
        for (final fixture in fixtures) {
          await _insertIntention(
            database,
            id: fixture.id.toCanonicalString(),
            title: 'Удаляемое намерение ${fixture.id.toCanonicalString()}',
            isArchived: fixture.isArchived,
            createdAt: DateTime.utc(2026, 9, 2, 10),
          );

          final result = await repository.execute(DeleteIntention(fixture.id));

          expect(result, _deleted(fixture.id));
          expect(
            _watched(await repository.watchIntention(fixture.id).first),
            isNull,
          );
          for (final scope in IntentionScope.values) {
            final page = await repository.getCatalogPage(
              IntentionCatalogQuery(
                scope: scope,
                titleFilter: null,
                order: IntentionCatalogOrder.createdAtDescending,
                pageSize: 100,
              ),
            );
            expect(
              _catalogItems(page).map((summary) => summary.id),
              isNot(contains(fixture.id)),
            );
          }
        }

        expect(
          diagnostics.events.whereType<IntentionCommandDiagnosticsEvent>(),
          [
            _successfulCommand(IntentionCommandDiagnosticsType.delete),
            _successfulCommand(IntentionCommandDiagnosticsType.delete),
          ],
        );
      },
    );

    test(
      'возвращает not-found при удалении отсутствующего намерения',
      () async {
        final result = await repository.execute(
          DeleteIntention(_id(_firstUuid)),
        );

        expect(result, _failure<IntentionNotFoundFailure>());
        expect(diagnostics.events, [
          _failedCommand(
            IntentionCommandDiagnosticsType.delete,
            DiagnosticsFailureCode.notFound,
          ),
        ]);
      },
    );

    test('выполняет матрицу переходов readiness и архива без изменения несвязанных данных', () async {
      final transitions =
          <
            ({
              IntentionCommand Function(IntentionId) command,
              IntentionCommandDiagnosticsType commandType,
              IntentionReadiness? readiness,
              IntentionArchiveState? archiveState,
              List<
                ({
                  IntentionReadiness readiness,
                  IntentionArchiveState archiveState,
                })
              >
              fixtures,
            })
          >[
            (
              command: (IntentionId id) => EnableIntentionReadiness(id),
              commandType: IntentionCommandDiagnosticsType.enableReadiness,
              readiness: IntentionReadiness.ready,
              archiveState: null,
              fixtures: [
                (
                  readiness: IntentionReadiness.notReady,
                  archiveState: IntentionArchiveState.active,
                ),
                (
                  readiness: IntentionReadiness.notReady,
                  archiveState: IntentionArchiveState.archived,
                ),
                (
                  readiness: IntentionReadiness.ready,
                  archiveState: IntentionArchiveState.active,
                ),
                (
                  readiness: IntentionReadiness.ready,
                  archiveState: IntentionArchiveState.archived,
                ),
              ],
            ),
            (
              command: (IntentionId id) => DisableIntentionReadiness(id),
              commandType: IntentionCommandDiagnosticsType.disableReadiness,
              readiness: IntentionReadiness.notReady,
              archiveState: null,
              fixtures: [
                (
                  readiness: IntentionReadiness.ready,
                  archiveState: IntentionArchiveState.active,
                ),
                (
                  readiness: IntentionReadiness.ready,
                  archiveState: IntentionArchiveState.archived,
                ),
                (
                  readiness: IntentionReadiness.notReady,
                  archiveState: IntentionArchiveState.active,
                ),
                (
                  readiness: IntentionReadiness.notReady,
                  archiveState: IntentionArchiveState.archived,
                ),
              ],
            ),
            (
              command: (IntentionId id) => ArchiveIntention(id),
              commandType: IntentionCommandDiagnosticsType.archive,
              readiness: null,
              archiveState: IntentionArchiveState.archived,
              fixtures: [
                (
                  readiness: IntentionReadiness.notReady,
                  archiveState: IntentionArchiveState.active,
                ),
                (
                  readiness: IntentionReadiness.ready,
                  archiveState: IntentionArchiveState.active,
                ),
                (
                  readiness: IntentionReadiness.notReady,
                  archiveState: IntentionArchiveState.archived,
                ),
                (
                  readiness: IntentionReadiness.ready,
                  archiveState: IntentionArchiveState.archived,
                ),
              ],
            ),
            (
              command: (IntentionId id) => RestoreIntention(id),
              commandType: IntentionCommandDiagnosticsType.restore,
              readiness: null,
              archiveState: IntentionArchiveState.active,
              fixtures: [
                (
                  readiness: IntentionReadiness.notReady,
                  archiveState: IntentionArchiveState.archived,
                ),
                (
                  readiness: IntentionReadiness.ready,
                  archiveState: IntentionArchiveState.archived,
                ),
                (
                  readiness: IntentionReadiness.notReady,
                  archiveState: IntentionArchiveState.active,
                ),
                (
                  readiness: IntentionReadiness.ready,
                  archiveState: IntentionArchiveState.active,
                ),
              ],
            ),
          ];
      final transitionTimes = [
        for (var hour = 10; hour < 18; hour++) DateTime.utc(2026, 9, 3, hour),
      ];
      clock = _DeterministicClock(transitionTimes);
      repository = DriftPersonalGraphRepository(
        database,
        idGenerator,
        clock.call,
        diagnostics,
      );

      var sequence = 1;
      var transitionCount = 0;
      for (final transition in transitions) {
        for (final fixture in transition.fixtures) {
          final id = _idForSequence(sequence++);
          final title = 'Название $sequence';
          final description = 'Описание $sequence';
          final createdAt = DateTime.utc(2026, 9, 2, 10, sequence);
          await _insertIntention(
            database,
            id: id.toCanonicalString(),
            title: title,
            description: description,
            isActionReady: fixture.readiness == IntentionReadiness.ready,
            isArchived: fixture.archiveState == IntentionArchiveState.archived,
            createdAt: createdAt,
          );
          final expectedReadiness = transition.readiness ?? fixture.readiness;
          final expectedArchiveState =
              transition.archiveState ?? fixture.archiveState;
          final changesState =
              expectedReadiness != fixture.readiness ||
              expectedArchiveState != fixture.archiveState;
          final updatesBefore = writeTrace.updateStatements.length;

          final saved = _saved(
            await repository.execute(transition.command(id)),
          );

          expect(saved.id, id);
          expect(saved.title, title);
          expect(saved.description, description);
          expect(saved.createdAt.value, createdAt);
          expect(saved.readiness, expectedReadiness);
          expect(saved.archiveState, expectedArchiveState);
          if (changesState) {
            expect(saved.updatedAt.value, transitionTimes[transitionCount++]);
            expect(writeTrace.updateStatements, hasLength(updatesBefore + 1));
          } else {
            expect(saved.updatedAt.value, createdAt);
            expect(writeTrace.updateStatements, hasLength(updatesBefore));
          }

          final row = await (database.select(
            database.intentions,
          )..where((row) => row.id.equals(id.toCanonicalString()))).getSingle();
          expect(row.title, title);
          expect(row.description, description);
          expect(
            row.isActionReady,
            expectedReadiness == IntentionReadiness.ready,
          );
          expect(
            row.isArchived,
            expectedArchiveState == IntentionArchiveState.archived,
          );
          expect(row.createdAt, createdAt.microsecondsSinceEpoch);
          expect(row.updatedAt, saved.updatedAt.value.microsecondsSinceEpoch);
        }
      }

      expect(transitionCount, transitionTimes.length);
      expect(clock.calls, transitionTimes.length);
      expect(
        diagnostics.events,
        everyElement(
          isA<IntentionCommandDiagnosticsEvent>().having(
            (event) => event.status,
            'status',
            isA<DiagnosticsSucceeded>(),
          ),
        ),
      );
      expect(
        diagnostics.events.whereType<IntentionCommandDiagnosticsEvent>().map(
          (event) => event.commandType,
        ),
        [
          for (final transition in transitions)
            for (final _ in transition.fixtures) transition.commandType,
        ],
      );
    });

    test(
      'возвращает not-found для каждого отсутствующего state transition',
      () async {
        final id = _id(_firstUuid);
        final transitions =
            <
              ({
                IntentionCommand Function(IntentionId) command,
                IntentionCommandDiagnosticsType commandType,
              })
            >[
              (
                command: (IntentionId id) => EnableIntentionReadiness(id),
                commandType: IntentionCommandDiagnosticsType.enableReadiness,
              ),
              (
                command: (IntentionId id) => DisableIntentionReadiness(id),
                commandType: IntentionCommandDiagnosticsType.disableReadiness,
              ),
              (
                command: (IntentionId id) => ArchiveIntention(id),
                commandType: IntentionCommandDiagnosticsType.archive,
              ),
              (
                command: (IntentionId id) => RestoreIntention(id),
                commandType: IntentionCommandDiagnosticsType.restore,
              ),
            ];

        for (final transition in transitions) {
          expect(
            await repository.execute(transition.command(id)),
            _failure<IntentionNotFoundFailure>(),
          );
        }

        expect(clock.calls, 0);
        expect(writeTrace.updateStatements, isEmpty);
        expect(diagnostics.events, [
          for (final transition in transitions)
            _failedCommand(
              transition.commandType,
              DiagnosticsFailureCode.notFound,
            ),
        ]);
      },
    );

    test(
      'изолирует параллельные state transitions одного и разных намерений',
      () async {
        final firstId = _id(_firstUuid);
        final secondId = _id(_secondUuid);
        final createdAt = DateTime.utc(2026, 9, 2, 10);
        await _insertIntention(
          database,
          id: firstId.toCanonicalString(),
          title: 'Первое намерение',
          description: 'Первое описание',
          createdAt: createdAt,
        );
        await _insertIntention(
          database,
          id: secondId.toCanonicalString(),
          title: 'Второе намерение',
          description: 'Второе описание',
          isActionReady: true,
          isArchived: true,
          createdAt: createdAt,
        );
        clock = _DeterministicClock([
          DateTime.utc(2026, 9, 3, 10),
          DateTime.utc(2026, 9, 3, 11),
          DateTime.utc(2026, 9, 3, 12),
          DateTime.utc(2026, 9, 3, 13),
        ]);
        repository = DriftPersonalGraphRepository(
          database,
          idGenerator,
          clock.call,
          diagnostics,
        );

        final results = await Future.wait([
          repository.execute(EnableIntentionReadiness(firstId)),
          repository.execute(ArchiveIntention(firstId)),
          repository.execute(DisableIntentionReadiness(secondId)),
          repository.execute(RestoreIntention(secondId)),
        ]);

        final firstReadiness = _saved(results[0]);
        final firstArchive = _saved(results[1]);
        final secondReadiness = _saved(results[2]);
        final secondRestore = _saved(results[3]);
        expect(firstReadiness.id, firstId);
        expect(firstReadiness.readiness, IntentionReadiness.ready);
        expect(firstArchive.id, firstId);
        expect(firstArchive.archiveState, IntentionArchiveState.archived);
        expect(secondReadiness.id, secondId);
        expect(secondReadiness.readiness, IntentionReadiness.notReady);
        expect(secondRestore.id, secondId);
        expect(secondRestore.archiveState, IntentionArchiveState.active);

        final first = _watched(await repository.watchIntention(firstId).first);
        final second = _watched(
          await repository.watchIntention(secondId).first,
        );
        expect(first?.title, 'Первое намерение');
        expect(first?.description, 'Первое описание');
        expect(first?.readiness, IntentionReadiness.ready);
        expect(first?.archiveState, IntentionArchiveState.archived);
        expect(second?.title, 'Второе намерение');
        expect(second?.description, 'Второе описание');
        expect(second?.readiness, IntentionReadiness.notReady);
        expect(second?.archiveState, IntentionArchiveState.active);
        expect(clock.calls, 4);
      },
    );

    test('сохраняет success create, update и no-op при отказе diagnostics после commit', () async {
      var writerWasCalled = false;
      final diagnosticsWithFailingWriter = DeveloperDiagnosticsSink((_) {
        writerWasCalled = true;
        throw StateError('CANARY-diagnostics-writer-failure');
      });
      final id = _id(_firstUuid);
      clock = _DeterministicClock([
        DateTime.utc(2026, 9, 3, 12),
        DateTime.utc(2026, 9, 3, 13),
      ]);
      repository = DriftPersonalGraphRepository(
        database,
        idGenerator,
        clock.call,
        diagnosticsWithFailingWriter,
      );

      final created = _saved(
        await repository.execute(
          const CreateIntention(
            title: 'Исходное название',
            description: 'Исходное описание',
          ),
        ),
      );
      final updated = _saved(
        await repository.execute(
          UpdateIntention(
            id: id,
            title: 'Обновлённое название',
            description: 'Обновлённое описание',
          ),
        ),
      );
      final noOp = _saved(
        await repository.execute(
          UpdateIntention(
            id: id,
            title: 'Обновлённое название',
            description: 'Обновлённое описание',
          ),
        ),
      );

      expect(created.id, id);
      expect(updated.title, 'Обновлённое название');
      expect(noOp.id, updated.id);
      expect(noOp.title, updated.title);
      expect(noOp.description, updated.description);
      expect(noOp.createdAt, updated.createdAt);
      expect(noOp.updatedAt, updated.updatedAt);
      final row = await (database.select(
        database.intentions,
      )..where((row) => row.id.equals(id.toCanonicalString()))).getSingle();
      expect(row.titleSearchKey, 'обновлённое название');
      final snapshot = await repository.watchIntention(id).first;
      expect(snapshot, isA<ResultSuccess<GraphSnapshot<IntentionDetails?>>>());
      final watched =
          (snapshot as ResultSuccess<GraphSnapshot<IntentionDetails?>>)
              .value
              .value
              ?.intention;
      expect(watched?.id, id);
      expect(watched?.title, updated.title);
      expect(watched?.description, updated.description);
      expect(watched?.createdAt, updated.createdAt);
      expect(watched?.updatedAt, updated.updatedAt);
      expect(writerWasCalled, isTrue);
    });

    test(
      'сохраняет typed storage failure при отказе diagnostics writer',
      () async {
        final storageFailure = _InsertFailureInterceptor(
          SqliteException(
            extendedResultCode: SqlError.SQLITE_BUSY,
            message: 'CANARY-storage-failure',
          ),
        );
        var writerWasCalled = false;
        final diagnosticsWithFailingWriter = DeveloperDiagnosticsSink((_) {
          writerWasCalled = true;
          throw StateError('CANARY-diagnostics-writer-failure');
        });
        await database.close();
        database = AppDatabase(
          observeConfiguredLocalDatabaseConnection(
            openInMemoryLocalDatabase(),
            storageFailure,
          ),
        );
        await database.open();
        repository = DriftPersonalGraphRepository(
          database,
          idGenerator,
          clock.call,
          diagnosticsWithFailingWriter,
        );

        final result = await repository.execute(
          const CreateIntention(title: 'Намерение', description: null),
        );

        expect(result, _failure<IntentionUnavailableFailure>());
        expect(await database.select(database.intentions).get(), isEmpty);
        expect(writerWasCalled, isTrue);
      },
    );

    test(
      'отклоняет malformed raw command snapshots до typed Drift mapping',
      () async {
        final fixtures =
            <
              ({
                IntentionCommand Function(IntentionId) command,
                IntentionCommandDiagnosticsType commandType,
                bool isArchived,
                Map<String, Object?> overrides,
              })
            >[
              (
                command: (id) => UpdateIntention(
                  id: id,
                  title: 'Обновлённое название',
                  description: 'Обновлённое описание',
                ),
                commandType: IntentionCommandDiagnosticsType.update,
                isArchived: false,
                overrides: {
                  'title': Uint8List.fromList([1]),
                },
              ),
              (
                command: (id) => UpdateIntention(
                  id: id,
                  title: 'Исходное название',
                  description: 'Исходное описание',
                ),
                commandType: IntentionCommandDiagnosticsType.update,
                isArchived: false,
                overrides: {
                  'description': Uint8List.fromList([2]),
                },
              ),
              (
                command: EnableIntentionReadiness.new,
                commandType: IntentionCommandDiagnosticsType.enableReadiness,
                isArchived: false,
                overrides: const {'is_action_ready': 2},
              ),
              (
                command: ArchiveIntention.new,
                commandType: IntentionCommandDiagnosticsType.archive,
                isArchived: false,
                overrides: const {'is_archived': -1},
              ),
              (
                command: RestoreIntention.new,
                commandType: IntentionCommandDiagnosticsType.restore,
                isArchived: true,
                overrides: {
                  'title_search_key': Uint8List.fromList([3]),
                },
              ),
              (
                command: DisableIntentionReadiness.new,
                commandType: IntentionCommandDiagnosticsType.disableReadiness,
                isArchived: false,
                overrides: const {'title_search_key': ''},
              ),
              (
                command: RestoreIntention.new,
                commandType: IntentionCommandDiagnosticsType.restore,
                isArchived: true,
                overrides: const {'title_search_key': 'ключ\u0000поиска'},
              ),
              (
                command: DeleteIntention.new,
                commandType: IntentionCommandDiagnosticsType.delete,
                isArchived: false,
                overrides: const {'created_at': 1.5},
              ),
              (
                command: DeleteIntention.new,
                commandType: IntentionCommandDiagnosticsType.delete,
                isArchived: true,
                overrides: const {'updated_at': '1725271200000000'},
              ),
            ];
        final query = IntentionCatalogQuery(
          scope: IntentionScope.all,
          titleFilter: null,
          order: IntentionCatalogOrder.createdAtDescending,
          pageSize: 100,
        );

        for (var index = 0; index < fixtures.length; index++) {
          final fixture = fixtures[index];
          final id = _idForSequence(500 + index);
          final createdAt = DateTime.utc(2026, 9, 2, 10, index);
          await _insertIntention(
            database,
            id: id.toCanonicalString(),
            title: 'Исходное название',
            description: 'Исходное описание',
            isArchived: fixture.isArchived,
            createdAt: createdAt,
          );
          final revisionBefore = _firstCatalogPage(
            await repository.getCatalogPage(query),
          ).revision;
          writeTrace.overrideNextSelect(fixture.overrides);

          final result = await repository.execute(fixture.command(id));

          expect(result, _failure<IntentionCorruptionFailure>());
          expect(
            diagnostics.events
                .whereType<IntentionCommandDiagnosticsEvent>()
                .last,
            _failedCommand(
              fixture.commandType,
              DiagnosticsFailureCode.corruption,
            ),
          );
          final stored = await (database.select(
            database.intentions,
          )..where((row) => row.id.equals(id.toCanonicalString()))).getSingle();
          expect(stored.title, 'Исходное название');
          expect(stored.description, 'Исходное описание');
          expect(stored.isActionReady, isFalse);
          expect(stored.isArchived, fixture.isArchived);
          expect(stored.createdAt, createdAt.microsecondsSinceEpoch);
          expect(stored.updatedAt, createdAt.microsecondsSinceEpoch);
          final revisionAfter = _firstCatalogPage(
            await repository.getCatalogPage(query),
          ).revision;
          expect(
            revisionBefore.compareTo(revisionAfter),
            GraphRevisionOrder.same,
          );
        }

        expect(clock.calls, 0);
      },
    );

    test('откатывает create при malformed raw post-insert snapshot', () async {
      final query = IntentionCatalogQuery(
        scope: IntentionScope.all,
        titleFilter: null,
        order: IntentionCatalogOrder.createdAtDescending,
        pageSize: 100,
      );
      final revisionBefore = _firstCatalogPage(
        await repository.getCatalogPage(query),
      ).revision;
      writeTrace.overrideNextSelect(const {'is_action_ready': 2});

      final result = await repository.execute(
        const CreateIntention(
          title: 'Новое намерение',
          description: 'Новое описание',
        ),
      );

      expect(result, _failure<IntentionCorruptionFailure>());
      expect(await database.select(database.intentions).get(), isEmpty);
      expect(
        diagnostics.events.whereType<IntentionCommandDiagnosticsEvent>().last,
        _failedCommand(
          IntentionCommandDiagnosticsType.create,
          DiagnosticsFailureCode.corruption,
        ),
      );
      final revisionAfter = _firstCatalogPage(
        await repository.getCatalogPage(query),
      ).revision;
      expect(revisionBefore.compareTo(revisionAfter), GraphRevisionOrder.same);
    });

    test('откатывает update при malformed raw after snapshot', () async {
      final id = _id(_firstUuid);
      final createdAt = DateTime.utc(2026, 9, 2, 10);
      await _insertIntention(
        database,
        id: id.toCanonicalString(),
        title: 'Исходное название',
        description: 'Исходное описание',
        createdAt: createdAt,
      );
      final query = IntentionCatalogQuery(
        scope: IntentionScope.all,
        titleFilter: null,
        order: IntentionCatalogOrder.createdAtDescending,
        pageSize: 100,
      );
      final revisionBefore = _firstCatalogPage(
        await repository.getCatalogPage(query),
      ).revision;
      writeTrace.overrideSelectAfter(
        skippedNonEmptySelects: 2,
        overrides: const {'updated_at': 1.5},
      );

      final result = await repository.execute(
        UpdateIntention(
          id: id,
          title: 'Обновлённое название',
          description: 'Обновлённое описание',
        ),
      );

      expect(result, _failure<IntentionCorruptionFailure>());
      final stored = await (database.select(
        database.intentions,
      )..where((row) => row.id.equals(id.toCanonicalString()))).getSingle();
      expect(stored.title, 'Исходное название');
      expect(stored.description, 'Исходное описание');
      expect(stored.updatedAt, createdAt.microsecondsSinceEpoch);
      expect(
        diagnostics.events.whereType<IntentionCommandDiagnosticsEvent>().last,
        _failedCommand(
          IntentionCommandDiagnosticsType.update,
          DiagnosticsFailureCode.corruption,
        ),
      );
      final revisionAfter = _firstCatalogPage(
        await repository.getCatalogPage(query),
      ).revision;
      expect(revisionBefore.compareTo(revisionAfter), GraphRevisionOrder.same);
    });

    group('Создание с полным начальным состоянием', () {
      // «Выходные» созданы раньше «Дома»: собственные теги снимка следуют
      // порядку создания тегов, а не порядку выбора в команде.
      final weekendTagId = _tagId(tagFixtureId(firstTagNumber));
      final homeTagId = _tagId(tagFixtureId(lastTagNumber));
      final newId = _id(_firstUuid);
      final activeFavoriteId = _idForSequence(0x601);
      final archivedFavoriteId = _idForSequence(0x602);
      final createdAt = DateTime.utc(2026, 9, 3, 12);
      final allQuery = IntentionCatalogQuery(
        scope: IntentionScope.all,
        titleFilter: null,
        order: IntentionCatalogOrder.createdAtDescending,
        pageSize: 100,
      );
      final readyHomeQuery = IntentionCatalogQuery(
        scope: IntentionScope.active,
        readinessFilter: IntentionReadinessFilter.readyOnly,
        titleFilter: null,
        tagFilter: IntentionTagFilter(requiredTagIds: [homeTagId]),
        order: IntentionCatalogOrder.createdAtDescending,
        pageSize: 100,
      );

      setUp(() async {
        raw.execute('INSERT INTO tags (id, name) VALUES (?, ?)', [
          weekendTagId.toCanonicalString(),
          'Выходные',
        ]);
        raw.execute('INSERT INTO tags (id, name) VALUES (?, ?)', [
          homeTagId.toCanonicalString(),
          'Дом',
        ]);
        await _insertIntention(
          database,
          id: activeFavoriteId.toCanonicalString(),
          title: 'Активное избранное',
          createdAt: DateTime.utc(2026, 9, 1),
        );
        await _insertIntention(
          database,
          id: archivedFavoriteId.toCanonicalString(),
          title: 'Архивное избранное',
          isArchived: true,
          createdAt: DateTime.utc(2026, 9, 2),
        );
        // Последнее место полного порядка принадлежит архивному намерению.
        storeFavoriteMark(
          raw,
          intentionId: activeFavoriteId.toCanonicalString(),
          position: 2,
        );
        storeFavoriteMark(
          raw,
          intentionId: archivedFavoriteId.toCanonicalString(),
          position: 5,
        );
        writeTrace.operations.clear();
        writeTrace.updateStatements.clear();
      });

      final scenarios = [
        (
          name: 'минимальная команда',
          command: const CreateIntention(
            title: '  Убрать дом  ',
            description: '  Вымыть окна\n',
          ),
          readiness: IntentionReadiness.notReady,
          favoriteMark: FavoriteMark.notFavorite,
          withTags: false,
        ),
        for (final readiness in IntentionReadiness.values)
          for (final favoriteMark in FavoriteMark.values)
            for (final withTags in [false, true])
              (
                name: [
                  switch (readiness) {
                    IntentionReadiness.ready => 'готовность',
                    IntentionReadiness.notReady => 'без готовности',
                  },
                  switch (favoriteMark) {
                    FavoriteMark.favorite => 'избранное',
                    FavoriteMark.notFavorite => 'без избранного',
                  },
                  withTags ? 'два тега' : 'без тегов',
                ].join(', '),
                command: CreateIntention.withInitialState(
                  title: '  Убрать дом  ',
                  description: '  Вымыть окна\n',
                  readiness: readiness,
                  favoriteMark: favoriteMark,
                  tagIds: withTags
                      ? [homeTagId, weekendTagId, homeTagId]
                      : const <TagId>[],
                ),
                readiness: readiness,
                favoriteMark: favoriteMark,
                withTags: withTags,
              ),
      ];

      for (final scenario in scenarios) {
        test(
          '${scenario.name}: одна транзакция даёт целый пакет новой ревизии, '
          'совпадающий с повторным чтением графа',
          () async {
            final revisionBefore = _firstCatalogPage(
              await repository.getCatalogPage(allQuery),
            ).revision;
            final isFavorite = scenario.favoriteMark == FavoriteMark.favorite;
            final expectedTagIds = scenario.withTags
                ? [weekendTagId, homeTagId]
                : const <TagId>[];

            final result = await repository.execute(scenario.command);

            // Записи одной команды: строка намерения, назначения и место
            // избранного без последующих изменений строки намерения.
            expect(
              writeTrace.operations.where(
                (operation) => operation == LocalDatabaseSqlOperation.insert,
              ),
              hasLength(1 + expectedTagIds.length + (isFavorite ? 1 : 0)),
            );
            expect(
              writeTrace.operations,
              isNot(
                anyOf(
                  contains(LocalDatabaseSqlOperation.update),
                  contains(LocalDatabaseSqlOperation.delete),
                ),
              ),
            );
            expect(
              diagnostics.events.whereType<IntentionCommandDiagnosticsEvent>(),
              [_successfulCommand(IntentionCommandDiagnosticsType.create)],
            );
            expect(
              diagnostics.events.whereType<TagCommandDiagnosticsEvent>(),
              isEmpty,
            );

            final confirmed = _confirmedCommand(result);
            expect(
              confirmed.revision.compareTo(revisionBefore),
              GraphRevisionOrder.newer,
            );
            final saved = _commandSuccess(result) as IntentionSaved;
            final created = saved.catalogMutation as IntentionCatalogCreated;
            expect(saved.catalogMutations, [same(created)]);
            expect(confirmed.changes, [
              same(created),
              for (final tagId in expectedTagIds)
                isA<TagAssignmentChangedChange>()
                    .having(
                      (change) => change.assignment,
                      'assignment',
                      TagAssignment(tagId: tagId, intentionId: newId),
                    )
                    .having(
                      (change) => change.state,
                      'state',
                      TagAssignmentState.assigned,
                    ),
            ]);

            final intention = saved.intention;
            expect(intention.id, newId);
            expect(intention.title, 'Убрать дом');
            expect(intention.description, '  Вымыть окна\n');
            expect(intention.readiness, scenario.readiness);
            expect(intention.archiveState, IntentionArchiveState.active);
            expect(intention.createdAt.value, createdAt);
            expect(intention.updatedAt, intention.createdAt);
            expect(idGenerator.generated, [newId]);
            expect(clock.calls, 1);

            final summary = created.entry.summary;
            expect(summary.id, newId);
            expect(summary.readiness, scenario.readiness);
            expect(summary.favoriteMark, scenario.favoriteMark);
            expect(summary.archiveState, IntentionArchiveState.active);
            expect(summary.createdAt, intention.createdAt);
            expect(summary.updatedAt, intention.createdAt);
            expect(summary.tags.map((tag) => tag.id), expectedTagIds);
            expect(
              summary.tags.map((tag) => tag.name.value),
              scenario.withTags ? ['Выходные', 'Дом'] : isEmpty,
            );
            final matchesReadyHome =
                scenario.readiness == IntentionReadiness.ready &&
                scenario.withTags;
            expect(created.entry.matches(readyHomeQuery), matchesReadyHome);

            final page = _firstCatalogPage(
              await repository.getCatalogPage(allQuery),
            );
            expect(
              page.revision.compareTo(confirmed.revision),
              GraphRevisionOrder.same,
            );
            expect(
              _summaryFacts(page.items.singleWhere((item) => item.id == newId)),
              _summaryFacts(summary),
            );
            expect(
              _catalogItems(await repository.getCatalogPage(readyHomeQuery))
                  .map((item) => item.id),
              matchesReadyHome ? [newId] : isEmpty,
            );
            expect(
              (await _tagAssignments(
                repository,
                newId,
              )).items.map((tag) => tag.id),
              expectedTagIds,
            );
            final details = await _details(repository, newId);
            expect(details.intention.readiness, scenario.readiness);
            expect(details.favoriteMark, scenario.favoriteMark);
            expect(_favoritePlaces(raw), [
              (activeFavoriteId.toCanonicalString(), 2),
              (archivedFavoriteId.toCanonicalString(), 5),
              if (isFavorite) (newId.toCanonicalString(), 6),
            ]);
            final favorites = await _favoriteIntentions(repository);
            expect(favorites.items.map((row) => row.id), [
              activeFavoriteId,
              if (isFavorite) newId,
            ]);
            expect(favorites.archivedCount, 1);
          },
        );
      }

      test(
        'отсутствующие выбранные теги отклоняют всё создание с точным набором '
        'без записи, генерации идентификатора и новой ревизии',
        () async {
          final firstMissing = _tagId(tagFixtureId(777));
          final secondMissing = _tagId(tagFixtureId(778));
          final revisionBefore = _firstCatalogPage(
            await repository.getCatalogPage(allQuery),
          ).revision;
          final intentionsBefore = _storedRows(raw, 'intentions');
          final placesBefore = _favoritePlaces(raw);
          writeTrace.operations.clear();

          final result = await repository.execute(
            CreateIntention.withInitialState(
              title: 'Убрать дом',
              description: null,
              readiness: IntentionReadiness.ready,
              favoriteMark: FavoriteMark.favorite,
              tagIds: [firstMissing, homeTagId, secondMissing],
            ),
          );

          expect(
            result,
            isA<ResultFailure<ConfirmedGraphResult<IntentionCommandSuccess>>>()
                .having(
                  (result) => result.failure,
                  'failure',
                  isA<IntentionCreationTagsMissingFailure>().having(
                    (failure) => failure.missingTagIds,
                    'missingTagIds',
                    {firstMissing, secondMissing},
                  ),
                ),
          );
          expect(
            writeTrace.operations,
            isNot(
              anyOf(
                contains(LocalDatabaseSqlOperation.insert),
                contains(LocalDatabaseSqlOperation.update),
                contains(LocalDatabaseSqlOperation.delete),
              ),
            ),
          );
          expect(idGenerator.generated, isEmpty);
          expect(clock.calls, 0);
          expect(_storedRows(raw, 'intentions'), intentionsBefore);
          expect(_storedRows(raw, 'tag_assignments'), isEmpty);
          expect(_favoritePlaces(raw), placesBefore);
          expect(
            _firstCatalogPage(await repository.getCatalogPage(allQuery))
                .revision
                .compareTo(revisionBefore),
            GraphRevisionOrder.same,
          );
          expect(
            diagnostics.events.whereType<IntentionCommandDiagnosticsEvent>(),
            [
              _failedCommand(
                IntentionCommandDiagnosticsType.create,
                DiagnosticsFailureCode.validation,
              ),
            ],
          );
        },
      );

      test('переименованный выбранный тег назначается по идентичности с '
          'актуальным названием без создания нового тега', () async {
        final renamed = await repository.execute(
          RenameTag(tagId: homeTagId, name: TagName.fromInput('Быт')),
        );
        expect(renamed, isA<TagCommandSucceeded>());

        final saved = _commandSuccess(
          await repository.execute(
            CreateIntention.withInitialState(
              title: 'Убрать дом',
              description: null,
              readiness: IntentionReadiness.notReady,
              favoriteMark: FavoriteMark.notFavorite,
              tagIds: [homeTagId],
            ),
          ),
        ) as IntentionSaved;

        expect(
          saved.catalogMutation.after!.summary.tags.map(
            (tag) => (tag.id, tag.name.value),
          ),
          [(homeTagId, 'Быт')],
        );
        expect(
          (await _tagAssignments(
            repository,
            newId,
          )).items.map((tag) => (tag.id, tag.name.value)),
          [(homeTagId, 'Быт')],
        );
        expect(_storedRows(raw, 'tags'), hasLength(2));
      });

      test('недопустимое название с полным начальным состоянием отклоняется '
          'проверкой текста без чтения тегов и записи', () async {
        writeTrace.operations.clear();

        final result = await repository.execute(
          CreateIntention.withInitialState(
            title: '   ',
            description: null,
            readiness: IntentionReadiness.ready,
            favoriteMark: FavoriteMark.favorite,
            tagIds: [homeTagId],
          ),
        );

        expect(
          result,
          _textValidationFailure(
            field: IntentionTextField.title,
            reason: IntentionTextValidationReason.empty,
          ),
        );
        expect(writeTrace.operations, isEmpty);
        expect(idGenerator.generated, isEmpty);
        expect(clock.calls, 0);
        expect(_storedRows(raw, 'tag_assignments'), isEmpty);
      });
    });
  });
}

ConfirmedGraphResult<IntentionCommandSuccess> _confirmedCommand(
  Result<ConfirmedGraphResult<IntentionCommandSuccess>> result,
) {
  expect(
    result,
    isA<ResultSuccess<ConfirmedGraphResult<IntentionCommandSuccess>>>(),
  );
  return (result
          as ResultSuccess<ConfirmedGraphResult<IntentionCommandSuccess>>)
      .value;
}

/// Наблюдаемые поля сводки каталога, включая собственные теги и отметку.
List<Object?> _summaryFacts(IntentionSummary summary) => [
  summary.id,
  summary.title,
  summary.hasDescription,
  summary.readiness,
  summary.archiveState,
  summary.activeRelationCount,
  summary.createdAt,
  summary.updatedAt,
  [for (final tag in summary.tags) (tag.id, tag.name.value)],
  summary.favoriteMark,
];

Future<TagAssignmentsSnapshot> _tagAssignments(
  DriftPersonalGraphRepository repository,
  IntentionId id,
) async => switch (await repository.getTagAssignments(id)) {
  GraphResultSuccess(:final value) => value,
  GraphResultFailure(:final failure) => throw TestFailure(
    'Чтение назначений завершилось отказом $failure.',
  ),
};

Future<FavoriteIntentionsSnapshot> _favoriteIntentions(
  DriftPersonalGraphRepository repository,
) async => switch (await repository.getFavoriteIntentions()) {
  GraphResultSuccess(:final value) => value,
  GraphResultFailure(:final failure) => throw TestFailure(
    'Чтение избранного завершилось отказом $failure.',
  ),
};

Future<IntentionDetails> _details(
  DriftPersonalGraphRepository repository,
  IntentionId id,
) async {
  final result = await repository.watchIntention(id).first;
  expect(result, isA<ResultSuccess<GraphSnapshot<IntentionDetails?>>>());
  return (result as ResultSuccess<GraphSnapshot<IntentionDetails?>>)
      .value
      .value!;
}

/// Места избранного в порядке единого списка.
List<(String, int)> _favoritePlaces(Database raw) => [
  for (final row in raw.select(
    'SELECT intention_id, position FROM favorite_intentions ORDER BY position',
  ))
    (row['intention_id'] as String, row['position'] as int),
];

List<Map<String, Object?>> _storedRows(Database raw, String table) => [
  for (final row in raw.select('SELECT * FROM $table ORDER BY 1')) {...row},
];

const _firstUuid = '018f0b5d-6b2e-7c80-8000-000000000401';
const _secondUuid = '018f0b5d-6b2e-7c80-8000-000000000402';

Intention _saved(Result<ConfirmedGraphResult<IntentionCommandSuccess>> result) {
  final success = _commandSuccess(result);
  expect(success, isA<IntentionSaved>());
  return (success as IntentionSaved).intention;
}

IntentionCommandSuccess _commandSuccess(
  Result<ConfirmedGraphResult<IntentionCommandSuccess>> result,
) {
  expect(
    result,
    isA<ResultSuccess<ConfirmedGraphResult<IntentionCommandSuccess>>>(),
  );
  final confirmed =
      (result as ResultSuccess<ConfirmedGraphResult<IntentionCommandSuccess>>)
          .value;
  expect(confirmed.changes, isNotEmpty);
  expect(
    confirmed.changes,
    everyElement(
      isA<GraphChange>().having(
        (change) => change.revision.compareTo(confirmed.revision),
        'revision',
        GraphRevisionOrder.same,
      ),
    ),
  );
  return confirmed.value;
}

ConfirmedGraphResult<TagCommandSuccess> _tagCommandSuccess(
  TagCommandResult result,
) {
  expect(result, isA<TagCommandSucceeded>());
  return (result as TagCommandSucceeded).value;
}

TagId _tagId(String value) => switch (TagId.decode(value)) {
  TagIdDecodingSuccess(:final id) => id,
  InvalidTagIdDecoding() => throw ArgumentError.value(value, 'value'),
};

IntentionCatalogFirstPage _firstCatalogPage(
  Result<IntentionCatalogPage> result,
) {
  expect(result, isA<ResultSuccess<IntentionCatalogPage>>());
  final page = (result as ResultSuccess<IntentionCatalogPage>).value;
  expect(page, isA<IntentionCatalogFirstPage>());
  return page as IntentionCatalogFirstPage;
}

Matcher _failure<TFailure extends IntentionFailure>() =>
    isA<ResultFailure<ConfirmedGraphResult<IntentionCommandSuccess>>>().having(
      (result) => result.failure,
      'failure',
      isA<TFailure>(),
    );

Matcher _textValidationFailure({
  required IntentionTextField field,
  required IntentionTextValidationReason reason,
}) =>
    isA<ResultFailure<ConfirmedGraphResult<IntentionCommandSuccess>>>().having(
      (result) => result.failure,
      'failure',
      isA<IntentionTextInputValidationFailure>()
          .having((failure) => failure.textFailure.field, 'field', field)
          .having((failure) => failure.textFailure.reason, 'reason', reason),
    );

Matcher _successfulCommand(IntentionCommandDiagnosticsType commandType) =>
    isA<IntentionCommandDiagnosticsEvent>()
        .having((event) => event.commandType, 'commandType', commandType)
        .having((event) => event.status, 'status', isA<DiagnosticsSucceeded>());

Matcher _failedCommand(
  IntentionCommandDiagnosticsType commandType,
  DiagnosticsFailureCode failureCode,
) => isA<IntentionCommandDiagnosticsEvent>()
    .having((event) => event.commandType, 'commandType', commandType)
    .having(
      (event) => event.status,
      'status',
      isA<DiagnosticsFailed>().having(
        (status) => status.code,
        'code',
        failureCode,
      ),
    );

IntentionId _id(String value) => switch (IntentionId.decode(value)) {
  IntentionIdDecodingSuccess(:final id) => id,
  InvalidIntentionIdDecoding() => throw ArgumentError.value(value, 'value'),
};

IntentionId _idForSequence(int value) =>
    _id('018f0b5d-6b2e-7c80-8000-${value.toRadixString(16).padLeft(12, '0')}');

Intention? _watched(Result<GraphSnapshot<IntentionDetails?>> result) {
  expect(result, isA<ResultSuccess<GraphSnapshot<IntentionDetails?>>>());
  return (result as ResultSuccess<GraphSnapshot<IntentionDetails?>>)
      .value
      .value
      ?.intention;
}

Matcher _deleted(IntentionId id) =>
    isA<ResultSuccess<ConfirmedGraphResult<IntentionCommandSuccess>>>().having(
      (result) => result.value.value,
      'value',
      isA<IntentionDeleted>().having((success) => success.id, 'id', id),
    );

List<IntentionSummary> _catalogItems(Result<IntentionCatalogPage> result) {
  expect(result, isA<ResultSuccess<IntentionCatalogPage>>());
  return (result as ResultSuccess<IntentionCatalogPage>).value.items;
}

Future<void> _insertIntention(
  AppDatabase database, {
  required String id,
  required String title,
  String? description,
  bool isActionReady = false,
  bool isArchived = false,
  required DateTime createdAt,
  DateTime? updatedAt,
}) => database
    .into(database.intentions)
    .insert(
      IntentionsCompanion.insert(
        id: id,
        title: title,
        description: Value(description),
        isActionReady: Value(isActionReady),
        isArchived: Value(isArchived),
        createdAt: createdAt.microsecondsSinceEpoch,
        updatedAt: (updatedAt ?? createdAt).microsecondsSinceEpoch,
      ),
    );

final class _DeterministicIntentionIdGenerator implements IntentionIdGenerator {
  _DeterministicIntentionIdGenerator(Iterable<IntentionId> ids)
    : _ids = List.unmodifiable(ids);

  final List<IntentionId> _ids;
  final List<IntentionId> generated = [];

  @override
  IntentionId generate() {
    if (generated.length == _ids.length) {
      throw StateError('Последовательность идентификаторов исчерпана.');
    }
    final id = _ids[generated.length];
    generated.add(id);
    return id;
  }
}

final class _DeterministicClock {
  _DeterministicClock(Iterable<DateTime> values)
    : _values = List.unmodifiable(values);

  final List<DateTime> _values;
  var calls = 0;

  DateTime call() {
    if (calls == _values.length) {
      throw StateError('Последовательность времени исчерпана.');
    }
    return _values[calls++];
  }
}

final class _WriteTrace extends LocalDatabaseConnectionObserver {
  final List<LocalDatabaseSqlOperation> operations = [];
  final List<String> updateStatements = [];
  Map<String, Object?>? _nextSelectOverrides;
  var _nonEmptySelectsToSkip = 0;
  String? _requiredColumn;

  void overrideNextSelect(Map<String, Object?> overrides) {
    overrideSelectAfter(skippedNonEmptySelects: 0, overrides: overrides);
  }

  void overrideSelectAfter({
    required int skippedNonEmptySelects,
    required Map<String, Object?> overrides,
  }) {
    if (_nextSelectOverrides != null) {
      throw StateError('Предыдущая подмена raw SELECT ещё не использована.');
    }
    _nonEmptySelectsToSkip = skippedNonEmptySelects;
    _nextSelectOverrides = overrides;
    _requiredColumn = null;
  }

  /// Подменяет строки непустого SELECT с указанным столбцом после пропуска
  /// заданного числа таких же чтений.
  void overrideSelectWithColumn(
    String column, {
    required int skippedMatchingSelects,
    required Map<String, Object?> overrides,
  }) {
    overrideSelectAfter(
      skippedNonEmptySelects: skippedMatchingSelects,
      overrides: overrides,
    );
    _requiredColumn = column;
  }

  @override
  void beforeStatement(LocalDatabaseSqlStatement statement) {
    operations.add(statement.operation);
    if (statement.operation == LocalDatabaseSqlOperation.update) {
      updateStatements.add(statement.statements.single);
    }
  }

  @override
  List<Map<String, Object?>> afterSelect(
    LocalDatabaseSqlStatement statement,
    List<Map<String, Object?>> rows,
  ) {
    final overrides = _nextSelectOverrides;
    if (overrides == null || rows.isEmpty) return rows;
    final column = _requiredColumn;
    if (column != null && !rows.first.containsKey(column)) return rows;
    if (_nonEmptySelectsToSkip > 0) {
      _nonEmptySelectsToSkip--;
      return rows;
    }
    _nextSelectOverrides = null;
    _requiredColumn = null;
    return [
      for (final row in rows) {...row, ...overrides},
    ];
  }
}

final class _InsertFailureInterceptor extends LocalDatabaseConnectionObserver {
  _InsertFailureInterceptor(this.failure);

  final Object failure;

  @override
  void beforeStatement(LocalDatabaseSqlStatement statement) {
    if (statement.operation == LocalDatabaseSqlOperation.insert) throw failure;
  }
}
