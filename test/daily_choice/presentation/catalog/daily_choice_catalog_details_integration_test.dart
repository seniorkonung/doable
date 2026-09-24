import 'package:doable/src/daily_choice/application/daily_choice_command.dart';
import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_id.dart';
import 'package:doable/src/daily_choice/presentation/catalog/daily_choice_catalog_state.dart';
import 'package:doable/src/daily_choice/presentation/catalog/daily_choice_catalog_view_model.dart';
import 'package:doable/src/daily_choice/presentation/details/daily_choice_details_state.dart';
import 'package:doable/src/daily_choice/presentation/details/daily_choice_details_view_model.dart';
import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/in_memory_diagnostics_sink.dart';

String _uuid(int number) =>
    '018f0b5d-6b2e-7c80-8000-${number.toRadixString(16).padLeft(12, '0')}';

DailyChoiceId _choice(int number) =>
    (DailyChoiceId.decode(_uuid(number)) as DailyChoiceIdDecodingSuccess).id;

Future<void> _until(bool Function() condition) async {
  for (var attempt = 0; attempt < 100 && !condition(); attempt++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(condition(), isTrue);
}

void main() {
  test(
    'реальный каталог и подробности согласуют дубликаты и изменения графа',
    () async {
      final database = AppDatabase(openInMemoryLocalDatabase());
      await database.open();
      addTearDown(database.close);
      for (final number in [1, 2, 3]) {
        await database.customStatement(
          '''INSERT INTO intentions
           (id, title, is_action_ready, is_archived, created_at, updated_at)
           VALUES (?, ?, ?, 0, 1, 1)''',
          [_uuid(number), 'Намерение $number', number == 3 ? 1 : 0],
        );
      }
      for (final (number, source, target) in [(101, 1, 2), (102, 2, 3)]) {
        await database.customStatement(
          '''INSERT INTO long_term_relations
           (id, source_intention_id, related_intention_id,
            type, priority, is_archived)
           VALUES (?, ?, ?, 'need', 2, 0)''',
          [_uuid(number), _uuid(source), _uuid(target)],
        );
      }
      for (var number = 201; number <= 251; number++) {
        await database.customStatement(
          '''INSERT INTO daily_choices
           (id, source_intention_id, selected_intention_id, choice_date,
            is_completed) VALUES (?, ?, ?, '2026-09-24', 0)''',
          [_uuid(number), _uuid(1), _uuid(3)],
        );
        await database.customStatement(
          '''INSERT INTO daily_choice_path_steps
           (id, daily_choice_id, long_term_relation_id, previous_step_id)
           VALUES (?, ?, ?, NULL)''',
          [_uuid(number + 1000), _uuid(number), _uuid(101)],
        );
        await database.customStatement(
          '''INSERT INTO daily_choice_path_steps
           (id, daily_choice_id, long_term_relation_id, previous_step_id)
           VALUES (?, ?, ?, ?)''',
          [
            _uuid(number + 2000),
            _uuid(number),
            _uuid(102),
            _uuid(number + 1000),
          ],
        );
      }

      final repository = DriftPersonalGraphRepository(
        database,
        UuidV7IntentionIdGenerator(),
        () => DateTime.utc(2026, 9, 24),
        InMemoryDiagnosticsSink(),
      );
      final container = ProviderContainer(
        overrides: [
          personalGraphRepositoryProvider.overrideWith((ref) => repository),
        ],
      );
      addTearDown(container.dispose);
      final subscription = container.listen(
        dailyChoiceCatalogViewModelProvider,
        (_, _) {},
      );
      addTearDown(subscription.close);
      DailyChoiceCatalogLoaded catalog() =>
          container.read(dailyChoiceCatalogViewModelProvider)
              as DailyChoiceCatalogLoaded;
      final model = container.read(
        dailyChoiceCatalogViewModelProvider.notifier,
      );
      final coordinator = container.read(
        graphCommandCoordinatorProvider.notifier,
      );

      await _until(
        () =>
            container.read(dailyChoiceCatalogViewModelProvider)
                is DailyChoiceCatalogLoaded,
      );
      expect(catalog().totalCount, 51);
      expect(catalog().items, hasLength(50));
      expect(catalog().items.first.id, _choice(251));
      expect(catalog().nextCursor, isNotNull);
      await model.loadMore();
      expect(catalog().items.map((item) => item.id).toSet(), {
        _choice(201),
        for (var number = 202; number <= 251; number++) _choice(number),
      });
      expect(catalog().items.last.id, _choice(201));

      final details = DailyChoiceDetailsViewModel(repository, _choice(201));
      addTearDown(details.dispose);
      await _until(() => details.state is DailyChoiceDetailsLoaded);
      DailyChoiceDetailsLoaded opened() =>
          details.state as DailyChoiceDetailsLoaded;
      expect(opened().details.choice.id, _choice(201));
      expect(
        opened().details.path.map(
          (step) => step.relation.id.toCanonicalString(),
        ),
        [_uuid(101), _uuid(102)],
      );
      expect(
        opened().details.path.last.related.id,
        opened().details.selected.id,
      );

      final update = coordinator.acceptDailyChoiceUpdate(
        UpdateDailyChoiceFields(
          choiceId: _choice(201),
          patch: DailyChoiceFieldsPatch(
            date: DailyChoiceFieldSet(CalendarDate.fromParts(2026, 9, 25)),
            isCompleted: const DailyChoiceFieldSet(true),
          ),
        ),
      ) as DailyChoiceCommandAccepted;
      expect(await update.future, isA<DailyChoiceCommandCompletion>());
      await _until(
        () =>
            catalog().freshness == DailyChoiceCatalogFreshness.current &&
            catalog().items.first.id == _choice(201) &&
            opened().details.choice.isCompleted,
      );
      expect(catalog().totalCount, 51);
      expect(catalog().items.first.date, CalendarDate.fromParts(2026, 9, 25));
      expect(opened().details.choice.date, catalog().items.first.date);

      final rename = coordinator.acceptExisting(
        UpdateIntention(
          id: opened().details.source.id,
          title: 'Новое основание',
          description: null,
        ),
        presentationTitle: 'Намерение 1',
      ) as IntentionCommandAccepted;
      await rename.future;
      await _until(
        () =>
            catalog().freshness == DailyChoiceCatalogFreshness.current &&
            catalog().items.first.source.title == 'Новое основание' &&
            opened().details.source.title == 'Новое основание',
      );
      expect(catalog().totalCount, 51);

      final deletion = coordinator.acceptDailyChoiceDelete(
        DeleteDailyChoice(_choice(201)),
      ) as DailyChoiceCommandAccepted;
      await deletion.future;
      await _until(
        () =>
            catalog().freshness == DailyChoiceCatalogFreshness.current &&
            catalog().totalCount == 50 &&
            details.state is DailyChoiceDetailsNotFound,
      );
      expect(catalog().items, hasLength(50));
      expect(catalog().items.any((item) => item.id == _choice(201)), isFalse);
    },
  );
}
