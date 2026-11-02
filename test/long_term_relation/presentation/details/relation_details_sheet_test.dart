import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:doable/src/app/routing/app_router.gr.dart';
import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:doable/src/daily_choice/presentation/catalog/daily_choice_local_date_provider.dart';
import 'package:doable/src/design_system/components/priority_picker.dart';
import 'package:doable/src/design_system/components/relation_head.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/graph/presentation/graph_operation_presenter.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_command.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_projection.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_description.dart';
import 'package:doable/src/long_term_relation/presentation/details/relation_details_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/ordinary_page_test_app.dart';
import '../relation_graph_test_support.dart';
import 'relation_details_test_support.dart';

const _relatedPageText = 'Страница намерения';

void main() {
  // Общая поверхность сообщений предъявляет результат только в приложении с
  // фокусом.
  setUp(() {
    WidgetsBinding.instance.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    );
  });

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

  group('тип и приоритет', () {
    LongTermRelationDetails relation({
      LongTermRelationType type = LongTermRelationType.need,
      RelationPriority priority = RelationPriority.p2,
      RelationScope scope = RelationScope.active,
    }) => testRelationDetails(
      relationId: relationId,
      sourceId: testIntentionId(1),
      relatedId: testIntentionId(2),
      sourceTitle: 'быть здоровым',
      relatedTitle: 'много ходить',
      type: type,
      priority: priority,
      scope: scope,
    );

    RelationHead head(WidgetTester tester) =>
        tester.widget<RelationHead>(find.byType(RelationHead));

    PriorityPicker picker(WidgetTester tester) =>
        tester.widget<PriorityPicker>(find.byType(PriorityPicker));

    testWidgets('нажатие на другой тип меняет только тип, а после '
        'подтверждения панель остаётся открытой с новой линией и '
        'формулировкой', (tester) async {
      final semantics = tester.ensureSemantics();
      final repository = await _openSheet(tester);
      final before = relation();
      repository.watchAt(0).emitDetails(before, revision: revision);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Можно'));
      await tester.pump();

      final command =
          repository.relationCommands.single as UpdateLongTermRelation;
      expect(
        command.patch.type,
        isA<LongTermRelationFieldSet<LongTermRelationType>>().having(
          (patch) => patch.value,
          'value',
          LongTermRelationType.can,
        ),
      );
      expect(
        command.patch.priority,
        isA<LongTermRelationFieldUnchanged<RelationPriority>>(),
      );

      final after = relation(type: LongTermRelationType.can);
      repository.completeRelationUpdate(
        0,
        before: before.relation,
        after: after.relation,
        revision: const TestGraphRevision(2),
      );
      await tester.pump();
      repository.relationWatches.last.emitDetails(
        after,
        revision: const TestGraphRevision(2),
      );
      await tester.pumpAndSettle();

      expect(head(tester).kind, RelationHeadKind.can);
      expect(
        find.bySemanticsLabel('Чтобы быть здоровым, можно много ходить'),
        findsOneWidget,
      );
      semantics.dispose();
    });

    testWidgets('выбор приоритета сразу сохраняется и красит шапку, а '
        'выбранный приоритет ничего не меняет', (tester) async {
      final repository = await _openSheet(tester);
      final before = relation(priority: RelationPriority.p4);
      repository.watchAt(0).emitDetails(before, revision: revision);
      await tester.pumpAndSettle();

      await tester.tap(find.text('P4'));
      await tester.pump();
      expect(repository.relationCommands, isEmpty);

      await tester.tap(find.text('P1'));
      await tester.pump();

      final command =
          repository.relationCommands.single as UpdateLongTermRelation;
      expect(
        command.patch.priority,
        isA<LongTermRelationFieldSet<RelationPriority>>().having(
          (patch) => patch.value,
          'value',
          RelationPriority.p1,
        ),
      );

      final after = relation(priority: RelationPriority.p1);
      repository.completeRelationUpdate(
        0,
        before: before.relation,
        after: after.relation,
        revision: const TestGraphRevision(2),
      );
      await tester.pump();
      repository.relationWatches.last.emitDetails(
        after,
        revision: const TestGraphRevision(2),
      );
      await tester.pumpAndSettle();

      expect(head(tester).priority, DoablePriority.p1);
      expect(picker(tester).value, DoablePriority.p1);
    });

    testWidgets('архивированная связь показывает слово типа вместо '
        'переключателя, а приоритет меняется', (tester) async {
      final repository = await _openSheet(tester);
      repository
          .watchAt(0)
          .emitDetails(
            relation(scope: RelationScope.archived),
            revision: revision,
          );
      await tester.pumpAndSettle();

      expect(find.text('нужно'), findsOneWidget);
      expect(find.text('Можно'), findsNothing);

      await tester.tap(find.text('P1'));
      await tester.pump();

      expect(repository.relationCommands, hasLength(1));
    });

    testWidgets('операция, начатая до повторного открытия, оставляет '
        'подтверждённое содержание со статусом и недоступным управлением до '
        'своего конца', (tester) async {
      final semantics = tester.ensureSemantics();
      final repository = await _openSheet(tester);
      final before = relation();
      repository.watchAt(0).emitDetails(before, revision: revision);
      await tester.pumpAndSettle();
      await tester.tap(find.text('P1'));
      await tester.pump();

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Открыть'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      repository.relationWatches.last.emitDetails(before, revision: revision);
      await tester.pumpAndSettle();

      expect(picker(tester).value, DoablePriority.p2);
      expect(find.text('Сохранение изменений…'), findsOneWidget);
      expect(
        tester.getSemantics(find.bySemanticsLabel('Можно')),
        isSemantics(isEnabled: false),
      );
      expect(
        tester.getSemantics(find.bySemanticsLabel('Приоритет P3')),
        isSemantics(isEnabled: false),
      );
      expect(
        tester.getSemantics(find.bySemanticsLabel('Добавить описание')),
        isSemantics(isEnabled: false),
      );

      final after = relation(priority: RelationPriority.p1);
      repository.completeRelationUpdate(
        0,
        before: before.relation,
        after: after.relation,
        revision: const TestGraphRevision(2),
      );
      await tester.pump();
      repository.relationWatches.last.emitDetails(
        after,
        revision: const TestGraphRevision(2),
      );
      await tester.pumpAndSettle();

      expect(find.text('Сохранение изменений…'), findsNothing);
      await tester.tap(find.text('P3'));
      await tester.pump();
      expect(repository.relationCommands, hasLength(2));
      semantics.dispose();
    });

    testWidgets('отказ оставляет подтверждённый приоритет и объясняется '
        'внутри панели, а следующая правка снимает сообщение', (tester) async {
      final repository = await _openSheet(tester);
      repository.watchAt(0).emitDetails(relation(), revision: revision);
      await tester.pumpAndSettle();

      await tester.tap(find.text('P1'));
      await tester.pump();
      repository.failRelationCommand(
        0,
        const LongTermRelationUnavailableFailure(),
      );
      await tester.pumpAndSettle();

      expect(picker(tester).value, DoablePriority.p2);
      expect(
        find
            .text('Не удалось изменить связь. Повторите попытку.')
            .hitTestable(),
        findsOneWidget,
      );

      await tester.tap(find.text('P1'));
      await tester.pump();

      expect(repository.relationCommands, hasLength(2));
      expect(
        find.text('Не удалось изменить связь. Повторите попытку.'),
        findsNothing,
      );
    });
  });

  group('описание', () {
    const saved = 'Хотя бы раз в неделю';
    const failureMessage = 'Не удалось изменить связь. Повторите попытку.';
    Finder back() => find.bySemanticsLabel('Назад к связи');

    LongTermRelationDetails relation({
      String? description = saved,
      RelationScope scope = RelationScope.active,
    }) => testRelationDetails(
      relationId: relationId,
      sourceId: testIntentionId(1),
      relatedId: testIntentionId(2),
      description: description,
      scope: scope,
      createdAt: DateTime(2026, 3, 14, 12),
      updatedAt: DateTime(2026, 3, 14, 12),
    );

    Future<ControlledRelationDetailsRepository> openEditing(
      WidgetTester tester,
      LongTermRelationDetails details,
    ) async {
      final repository = await _openSheet(tester);
      repository.watchAt(0).emitDetails(details, revision: revision);
      await tester.pumpAndSettle();
      await tester.tap(
        find.text(details.description?.value ?? 'Добавить описание'),
      );
      await tester.pumpAndSettle();
      return repository;
    }

    Future<void> enterAndSave(WidgetTester tester, String text) async {
      await tester.enterText(find.byType(TextField), text);
      await tester.pump();
      await tester.tap(find.text('Сохранить'));
      await tester.pump();
    }

    testWidgets('нажатие на поле открывает изменение под полосой: шапка '
        'показывает слово типа, а приоритета и дат нет', (tester) async {
      final semantics = tester.ensureSemantics();
      await openEditing(tester, relation());

      expect(find.bySemanticsLabel('Описание связи'), findsOneWidget);
      expect(find.text('Описание'), findsOneWidget);
      expect(find.text(saved), findsOneWidget);
      expect(find.text('нужно'), findsOneWidget);
      expect(find.text('Можно'), findsNothing);
      expect(find.byType(PriorityPicker), findsNothing);
      expect(find.textContaining('Создано'), findsNothing);
      semantics.dispose();
    });

    testWidgets('строка архива скрыта на время изменения', (tester) async {
      await openEditing(tester, relation(scope: RelationScope.archived));

      expect(find.text('Сохранить'), findsOneWidget);
      expect(find.textContaining('Архивные связи'), findsNothing);
    });

    testWidgets('«Сохранить» доступна только при изменённом тексте', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await openEditing(tester, relation());
      final save = find.bySemanticsLabel('Сохранить');

      expect(tester.getSemantics(save), isSemantics(isEnabled: false));

      await tester.enterText(find.byType(TextField), '$saved!');
      await tester.pump();
      expect(tester.getSemantics(save), isSemantics(isEnabled: true));

      await tester.enterText(find.byType(TextField), saved);
      await tester.pump();
      expect(tester.getSemantics(save), isSemantics(isEnabled: false));
      semantics.dispose();
    });

    testWidgets('успех отправляет только описание и возвращает панель с новым '
        'текстом без сообщения', (tester) async {
      final repository = await openEditing(tester, relation());
      final before = relation();

      await enterAndSave(tester, 'Каждый день');

      final command =
          repository.relationCommands.single as UpdateLongTermRelation;
      expect(
        command.patch.description,
        isA<LongTermRelationDescriptionReplaced>(),
      );
      expect(
        command.patch.priority,
        isA<LongTermRelationFieldUnchanged<RelationPriority>>(),
      );

      final after = relation(description: 'Каждый день');
      repository.completeRelationUpdate(
        0,
        before: before.relation,
        after: after.relation,
        description: LongTermRelationDescription.fromInput('Каждый день'),
        revision: const TestGraphRevision(2),
      );
      await tester.pump();
      repository.relationWatches.last.emitDetails(
        after,
        revision: const TestGraphRevision(2),
      );
      await tester.pumpAndSettle();

      expect(find.text('Сохранить'), findsNothing);
      expect(find.text('Каждый день').hitTestable(), findsOneWidget);
      expect(find.byType(PriorityPicker), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('пробелы у связи без описания выходят из изменения без команды '
        'и сообщения, а дата остаётся прежней', (tester) async {
      final repository = await openEditing(tester, relation(description: null));

      await enterAndSave(tester, '   ');
      await tester.pumpAndSettle();

      expect(repository.relationCommands, isEmpty);
      expect(find.text('Сохранить'), findsNothing);
      expect(find.text('Добавить описание'), findsOneWidget);
      expect(find.text('Создано 14 мар.'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
    });

    for (final (reason, text, message) in const [
      ('слишком длинный текст', null, 'Используйте не более 4096 символов.'),
      ('NUL', 'до\u0000после', 'Введите корректный Unicode-текст без NUL.'),
    ]) {
      testWidgets(
        '$reason остаётся в поле и объясняется своей строкой, а новый '
        'ввод снимает объяснение',
        (tester) async {
          final repository = await openEditing(tester, relation());
          final entered = text ?? 'а' * 4097;

          await enterAndSave(tester, entered);
          await tester.pumpAndSettle();

          expect(repository.relationCommands, isEmpty);
          expect(find.text(entered), findsOneWidget);
          expect(find.text(message), findsOneWidget);

          await tester.enterText(find.byType(TextField), 'Исправлено');
          await tester.pump();

          expect(find.text(message), findsNothing);
        },
      );
    }

    testWidgets('пока сохранение выполняется, стрелка и поле недоступны, а '
        'отказ оставляет введённый текст на открытой панели', (tester) async {
      final semantics = tester.ensureSemantics();
      final repository = await openEditing(tester, relation());

      await enterAndSave(tester, 'Каждый день');

      expect(find.text('Сохранение изменений…'), findsOneWidget);
      expect(tester.getSemantics(back()), isSemantics(isEnabled: false));
      expect(tester.widget<TextField>(find.byType(TextField)).readOnly, isTrue);
      await tester.tap(back());
      await tester.pumpAndSettle();
      expect(find.text('Сохранить'), findsOneWidget);
      expect(find.text('Отменить изменения?'), findsNothing);

      repository.failRelationCommand(
        0,
        const LongTermRelationUnavailableFailure(),
      );
      await tester.pumpAndSettle();

      expect(find.text('Каждый день'), findsOneWidget);
      expect(find.text(failureMessage), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      expect(tester.getSemantics(back()), isSemantics(isEnabled: true));
      expect(
        tester.widget<TextField>(find.byType(TextField)).readOnly,
        isFalse,
      );
      semantics.dispose();
    });

    testWidgets('отказ записи виден над клавиатурой', (tester) async {
      tester.view
        ..physicalSize = const Size(390, 640)
        ..devicePixelRatio = 1
        ..viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.reset);
      final repository = await openEditing(tester, relation());

      await enterAndSave(tester, 'Каждый день');
      repository.failRelationCommand(
        0,
        const LongTermRelationUnavailableFailure(),
      );
      await tester.pumpAndSettle();

      expect(find.text(failureMessage).hitTestable(), findsOneWidget);
    });

    testWidgets('изменённый текст спрашивает перед уходом стрелкой: отказ от '
        'сброса возвращает текст, а сброс возвращает панель', (tester) async {
      final semantics = tester.ensureSemantics();
      final repository = await openEditing(tester, relation());

      await tester.enterText(find.byType(TextField), 'Черновик');
      await tester.pump();
      await tester.tap(back());
      await tester.pumpAndSettle();
      expect(find.text('Отменить изменения?'), findsOneWidget);

      await tester.tap(find.text('Продолжить правку'));
      await tester.pumpAndSettle();
      expect(find.text('Черновик'), findsOneWidget);
      expect(find.text('Сохранить'), findsOneWidget);

      await tester.tap(back());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Отменить'));
      await tester.pumpAndSettle();

      expect(find.text('Сохранить'), findsNothing);
      expect(find.text(saved).hitTestable(), findsOneWidget);
      expect(repository.relationCommands, isEmpty);
      semantics.dispose();
    });

    testWidgets('изменённый текст спрашивает перед закрытием панели: отказ от '
        'сброса оставляет изменение, а сброс закрывает панель', (tester) async {
      await openEditing(tester, relation());

      await tester.enterText(find.byType(TextField), 'Черновик');
      await tester.pump();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Отменить изменения?'), findsOneWidget);

      await tester.tap(find.text('Продолжить правку'));
      await tester.pumpAndSettle();
      expect(find.text('Черновик'), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Отменить'));
      await tester.pumpAndSettle();

      expect(find.text('Открыть').hitTestable(), findsOneWidget);
      expect(find.text('Черновик'), findsNothing);
    });

    testWidgets('без изменений стрелка возвращает панель, а системное «назад» '
        'закрывает её', (tester) async {
      final semantics = tester.ensureSemantics();
      await openEditing(tester, relation());

      await tester.tap(back());
      await tester.pumpAndSettle();
      expect(find.text('Сохранить'), findsNothing);
      expect(find.text(saved).hitTestable(), findsOneWidget);

      await tester.tap(find.text(saved));
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.text('Открыть').hitTestable(), findsOneWidget);
      expect(find.text('Отменить изменения?'), findsNothing);
      semantics.dispose();
    });

    testWidgets('закрытие панели во время сохранения не спрашивает, а отказ '
        'предъявляет оболочка', (tester) async {
      final repository = await openEditing(tester, relation());

      await enterAndSave(tester, 'Каждый день');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.text('Отменить изменения?'), findsNothing);
      expect(find.text('Открыть').hitTestable(), findsOneWidget);

      repository.failRelationCommand(
        0,
        const LongTermRelationUnavailableFailure(),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.textContaining(failureMessage), findsOneWidget);
    });

    testWidgets('удалённая связь завершает изменение, и панель закрывается '
        'без вопроса', (tester) async {
      final repository = await openEditing(tester, relation());

      await tester.enterText(find.byType(TextField), 'Черновик');
      await tester.pump();
      repository.watchAt(0).emitMissing(revision: const TestGraphRevision(2));
      await tester.pumpAndSettle();

      expect(find.text('Эта связь больше не существует.'), findsOneWidget);
      expect(find.text('Сохранить'), findsNothing);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.text('Отменить изменения?'), findsNothing);
      expect(find.text('Открыть').hitTestable(), findsOneWidget);
    });
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
        builder: (_, child) =>
            GraphOperationPresenter(child: child ?? const SizedBox.shrink()),
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
