import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:doable/src/app/routing/app_router.gr.dart';
import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:doable/src/daily_choice/presentation/catalog/daily_choice_local_date_provider.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_projection.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/long_term_relation/presentation/details/relation_details_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/ordinary_page_test_app.dart';
import '../relation_graph_test_support.dart';
import 'relation_details_test_support.dart';

const _relatedPageText = 'Страница намерения';

void main() {
  final relationId = testRelationId(1);
  const revision = TestGraphRevision(1);

  testWidgets('панель показывает связь в исходном направлении, описание, '
      'приоритет и одну дату новой связи', (tester) async {
    final semantics = tester.ensureSemantics();
    final repository = await _openSheet(tester);

    repository
        .watchAt(0)
        .emitDetails(
          testRelationDetails(
            relationId: relationId,
            sourceId: testIntentionId(1),
            relatedId: testIntentionId(2),
            sourceTitle: 'быть здоровым',
            relatedTitle: 'плавать',
            type: LongTermRelationType.can,
            priority: RelationPriority.p3,
            description: 'Хотя бы раз в неделю',
            createdAt: DateTime(2026, 3, 14, 12),
            updatedAt: DateTime(2026, 3, 14, 18),
          ),
          revision: revision,
        );
    await tester.pumpAndSettle();

    expect(
      find.bySemanticsLabel('Чтобы быть здоровым, можно плавать'),
      findsOneWidget,
    );
    expect(
      tester.getTopLeft(find.text('быть здоровым')).dy,
      lessThan(tester.getTopLeft(find.text('плавать')).dy),
    );
    expect(find.text('Хотя бы раз в неделю'), findsOneWidget);
    expect(
      tester.getSemantics(find.bySemanticsLabel('Приоритет P3')),
      isSemantics(isSelected: true),
    );
    expect(find.text('Создано 14 мар.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('без описания панель приглашает его добавить', (tester) async {
    final repository = await _openSheet(tester);

    repository
        .watchAt(0)
        .emitDetails(
          testRelationDetails(
            relationId: relationId,
            sourceId: testIntentionId(1),
            relatedId: testIntentionId(2),
          ),
          revision: revision,
        );
    await tester.pumpAndSettle();

    expect(find.text('Добавить описание'), findsOneWidget);
  });

  testWidgets('изменение в другой день добавляет дату изменения', (
    tester,
  ) async {
    final repository = await _openSheet(tester);

    repository
        .watchAt(0)
        .emitDetails(
          testRelationDetails(
            relationId: relationId,
            sourceId: testIntentionId(1),
            relatedId: testIntentionId(2),
            createdAt: DateTime(2026, 3, 14, 12),
            updatedAt: DateTime(2026, 10, 3, 12),
          ),
          revision: revision,
        );
    await tester.pumpAndSettle();

    expect(find.text('Создано 14 мар. · Изменено 3 окт.'), findsOneWidget);
  });

  testWidgets('архивированная связь называет архив панелью, отметкой и '
      'строкой, а архивированный участник — своей меткой', (tester) async {
    final semantics = tester.ensureSemantics();
    final repository = await _openSheet(tester);

    repository
        .watchAt(0)
        .emitDetails(
          testRelationDetails(
            relationId: relationId,
            sourceId: testIntentionId(1),
            relatedId: testIntentionId(2),
            sourceTitle: 'быть здоровым',
            relatedTitle: 'плавать',
            relatedArchiveState: IntentionArchiveState.archived,
            scope: RelationScope.archived,
          ),
          revision: revision,
        );
    await tester.pumpAndSettle();

    expect(
      find.bySemanticsLabel('Чтобы быть здоровым, нужно плавать. Архив'),
      findsOneWidget,
    );
    expect(
      find.text(
        'Архивные связи остаются в сохранённых путях и не предлагаются '
        'в новых.',
      ),
      findsOneWidget,
    );
    // Отметка связи после слова типа и метка участника после его названия.
    expect(find.text('Архив'), findsNWidgets(2));
    expect(
      find.bySemanticsLabel('Открыть страницу намерения: плавать. Архив'),
      findsOneWidget,
    );
    semantics.dispose();
  });

  testWidgets('загрузка и отсутствие связи различимы внутри панели', (
    tester,
  ) async {
    final repository = await _openSheet(tester);

    expect(find.text('Загружаем связь…'), findsOneWidget);

    repository.watchAt(0).emitMissing(revision: revision);
    await tester.pumpAndSettle();

    expect(find.text('Эта связь больше не существует.'), findsOneWidget);
    expect(find.text('Повторить'), findsNothing);
  });

  testWidgets('временный отказ чтения предлагает повтор, который показывает '
      'связь', (tester) async {
    final repository = await _openSheet(tester);

    repository.watchAt(0).fail(const LongTermRelationReadUnavailableFailure());
    await tester.pumpAndSettle();
    expect(
      find.text('Не удалось загрузить связь. Повторите попытку.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Повторить'));
    await tester.pump();
    repository
        .watchAt(1)
        .emitDetails(
          testRelationDetails(
            relationId: relationId,
            sourceId: testIntentionId(1),
            relatedId: testIntentionId(2),
            sourceTitle: 'быть здоровым',
          ),
          revision: revision,
        );
    await tester.pumpAndSettle();

    expect(find.text('быть здоровым'), findsOneWidget);
  });

  testWidgets('повреждение данных не предлагает бесполезный повтор', (
    tester,
  ) async {
    final repository = await _openSheet(tester);

    repository.watchAt(0).fail(const LongTermRelationReadCorruptionFailure());
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Сохранённые данные связи повреждены и не могут быть показаны.',
      ),
      findsOneWidget,
    );
    expect(find.text('Повторить'), findsNothing);
  });

  testWidgets('отказ обновления оставляет прежний снимок и предлагает повтор', (
    tester,
  ) async {
    final repository = await _openSheet(tester);
    final watch = repository.watchAt(0);
    watch.emitDetails(
      testRelationDetails(
        relationId: relationId,
        sourceId: testIntentionId(1),
        relatedId: testIntentionId(2),
        sourceTitle: 'быть здоровым',
      ),
      revision: revision,
    );
    await tester.pumpAndSettle();

    watch.fail(const LongTermRelationReadUnavailableFailure());
    await tester.pumpAndSettle();

    expect(find.text('быть здоровым'), findsOneWidget);
    expect(
      find.text(
        'Не удалось обновить подробные данные связи. Ранее подтверждённые '
        'данные по-прежнему показаны.',
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('Повторить'));
    await tester.pump();
    repository
        .watchAt(1)
        .emitDetails(
          testRelationDetails(
            relationId: relationId,
            sourceId: testIntentionId(1),
            relatedId: testIntentionId(2),
            sourceTitle: 'быть здоровым заново',
          ),
          revision: const TestGraphRevision(2),
        );
    await tester.pumpAndSettle();

    expect(find.text('быть здоровым заново'), findsOneWidget);
    expect(find.text('Повторить'), findsNothing);
  });

  testWidgets('название участника открывает его страницу поверх панели, а '
      'возврат показывает ту же панель', (tester) async {
    final repository = await _openSheet(tester);
    repository
        .watchAt(0)
        .emitDetails(
          testRelationDetails(
            relationId: relationId,
            sourceId: testIntentionId(1),
            relatedId: testIntentionId(2),
            relatedTitle: 'плавать',
          ),
          revision: revision,
        );
    await tester.pumpAndSettle();

    await tester.tap(find.text('плавать'));
    await tester.pumpAndSettle();

    expect(
      find.text('$_relatedPageText ${testIntentionId(2)}'),
      findsOneWidget,
    );
    expect(find.text('плавать'), findsNothing);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('плавать').hitTestable(), findsOneWidget);
    // Та же панель не читает связь заново.
    expect(repository.relationWatches, hasLength(1));
  });

  testWidgets('сообщение появляется над панелью, а не за её затемнением', (
    tester,
  ) async {
    final repository = await _openSheet(tester);
    repository
        .watchAt(0)
        .emitDetails(
          testRelationDetails(
            relationId: relationId,
            sourceId: testIntentionId(1),
            relatedId: testIntentionId(2),
          ),
          revision: revision,
        );
    await tester.pumpAndSettle();

    ScaffoldMessenger.of(tester.element(find.byType(TextButton)))
        .showSnackBar(const SnackBar(content: Text('Сообщение')));
    await tester.pumpAndSettle();

    expect(find.text('Сообщение').hitTestable(), findsOneWidget);
  });
}

/// Открывает панель связи над страницей и возвращает репозиторий, которым тест
/// отвечает на её чтение.
Future<ControlledRelationDetailsRepository> _openSheet(
  WidgetTester tester,
) async {
  final repository = ControlledRelationDetailsRepository();
  addTearDown(repository.dispose);
  final container = ProviderContainer(
    overrides: [
      personalGraphRepositoryProvider.overrideWithValue(repository),
      dailyChoiceLocalDateSourceProvider.overrideWithValue(
        () => DailyChoiceLocalDay(
          date: CalendarDate.fromParts(2026, 11, 2),
          untilNextDate: const Duration(hours: 1),
        ),
      ),
    ],
    retry: (retryCount, error) => null,
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: OrdinaryPageTestApp(
        locale: const Locale('ru'),
        routes: [
          NamedRouteDef(
            name: IntentionDetailsRoute.name,
            builder: (_, data) => Scaffold(
              body: Text(
                '$_relatedPageText '
                '${data.argsAs<IntentionDetailsRouteArgs>().intentionId}',
              ),
            ),
          ),
        ],
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => unawaited(
                showRelationDetailsSheet(context, testRelationId(1)),
              ),
              child: const Text('Открыть'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.tap(find.text('Открыть'));
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  return repository;
}
