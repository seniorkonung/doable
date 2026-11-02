import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:doable/src/app/routing/app_router.gr.dart';
import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:doable/src/daily_choice/presentation/catalog/daily_choice_local_date_provider.dart';
import 'package:doable/src/design_system/components/priority_picker.dart';
import 'package:doable/src/design_system/components/relation_head.dart';
import 'package:doable/src/design_system/components/sheet.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/graph/presentation/graph_operation_presenter.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_command.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_permissions.dart';
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
    expect(
      find.bySemanticsLabel('Открыть страницу намерения: быть здоровым'),
      findsOneWidget,
    );
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

  for (final (name, failure, message) in const [
    (
      'повреждение данных',
      LongTermRelationReadCorruptionFailure(),
      'Сохранённые данные связи повреждены и не могут быть показаны.',
    ),
    (
      'неожиданный отказ',
      LongTermRelationReadUnexpectedFailure(),
      'Не удалось загрузить связь из-за непредвиденной ошибки.',
    ),
  ]) {
    testWidgets('$name называет себя и не предлагает бесполезный повтор', (
      tester,
    ) async {
      final repository = await _openSheet(tester);

      repository.watchAt(0).fail(failure);
      await tester.pumpAndSettle();

      expect(find.text(message), findsOneWidget);
      expect(find.text('Повторить'), findsNothing);
    });
  }

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

  testWidgets('переименование и каскадное архивирование участника обновляют '
      'открытую панель', (tester) async {
    final semantics = tester.ensureSemantics();
    final repository = await _openSheet(tester);
    final watch = repository.watchAt(0);
    watch.emitDetails(
      testRelationDetails(
        relationId: relationId,
        sourceId: testIntentionId(1),
        relatedId: testIntentionId(2),
        sourceTitle: 'быть здоровым',
        relatedTitle: 'прежнее название',
      ),
      revision: revision,
    );
    await tester.pumpAndSettle();
    expect(find.text('прежнее название'), findsOneWidget);

    watch.emitDetails(
      testRelationDetails(
        relationId: relationId,
        sourceId: testIntentionId(1),
        relatedId: testIntentionId(2),
        sourceTitle: 'быть здоровым',
        relatedTitle: 'новое название',
        relatedArchiveState: IntentionArchiveState.archived,
        scope: RelationScope.archived,
      ),
      revision: const TestGraphRevision(2),
    );
    await tester.pumpAndSettle();

    expect(find.text('прежнее название'), findsNothing);
    expect(find.text('новое название'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Чтобы быть здоровым, нужно новое название. Архив'),
      findsOneWidget,
    );
    expect(find.textContaining('Архивные связи остаются'), findsOneWidget);
    semantics.dispose();
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

  group('параметры связи', () {
    const phrase = 'Чтобы быть здоровым, нужно много ходить';
    final snackBar = find.byType(SnackBar);

    LongTermRelationDetails relation({
      RelationScope scope = RelationScope.active,
      IntentionArchiveState sourceArchiveState = IntentionArchiveState.active,
      IntentionArchiveState relatedArchiveState = IntentionArchiveState.active,
      LongTermRelationPermissions permissions =
          const LongTermRelationPermissions.unrestricted(),
    }) => testRelationDetails(
      relationId: relationId,
      sourceId: testIntentionId(1),
      relatedId: testIntentionId(2),
      sourceTitle: 'быть здоровым',
      relatedTitle: 'много ходить',
      scope: scope,
      sourceArchiveState: sourceArchiveState,
      relatedArchiveState: relatedArchiveState,
      permissions: permissions,
    );

    Future<ControlledRelationDetailsRepository> openPanel(
      WidgetTester tester,
      LongTermRelationDetails details,
    ) async {
      final repository = await _openSheet(tester);
      repository.watchAt(0).emitDetails(details, revision: revision);
      await tester.pumpAndSettle();
      return repository;
    }

    Future<void> openMenu(WidgetTester tester) async {
      await tester.tap(find.bySemanticsLabel('Параметры связи'));
      await tester.pumpAndSettle();
    }

    Future<void> choose(WidgetTester tester, String item) async {
      await openMenu(tester);
      await tester.tap(find.text(item));
      await tester.pumpAndSettle();
    }

    /// Подтверждённое изменение: отвечает на команду и отдаёт новый снимок.
    Future<void> confirmUpdate(
      WidgetTester tester,
      ControlledRelationDetailsRepository repository, {
      required LongTermRelationDetails before,
      required LongTermRelationDetails after,
    }) async {
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
    }

    testWidgets('у активной связи меню предлагает архивирование и удаление, а '
        'изменения описания в нём нет', (tester) async {
      final semantics = tester.ensureSemantics();
      await openPanel(tester, relation());

      await openMenu(tester);

      expect(find.text('Архивировать').hitTestable(), findsOneWidget);
      expect(find.text('Удалить').hitTestable(), findsOneWidget);
      expect(find.text('Восстановить из архива'), findsNothing);
      expect(find.textContaining('Изменить'), findsNothing);
      semantics.dispose();
    });

    testWidgets('архивирование начинается после закрытия меню и отражается в '
        'панели без сообщения', (tester) async {
      final semantics = tester.ensureSemantics();
      final before = relation();
      final repository = await openPanel(tester, before);

      await choose(tester, 'Архивировать');

      expect(
        repository.relationCommands.single,
        isA<ArchiveLongTermRelation>(),
      );
      expect(find.text('Восстановить из архива'), findsNothing);
      expect(find.text('Сохранение изменений…'), findsOneWidget);

      await confirmUpdate(
        tester,
        repository,
        before: before,
        after: relation(scope: RelationScope.archived),
      );

      expect(find.text('Сохранение изменений…'), findsNothing);
      expect(
        find.bySemanticsLabel('Чтобы быть здоровым, нужно много ходить. Архив'),
        findsOneWidget,
      );
      expect(find.textContaining('Архивные связи остаются'), findsOneWidget);
      expect(snackBar, findsNothing);
      semantics.dispose();
    });

    testWidgets('восстановление отражается в панели без сообщения', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final before = relation(scope: RelationScope.archived);
      final repository = await openPanel(tester, before);

      await openMenu(tester);
      expect(find.text('Архивировать'), findsNothing);
      await tester.tap(find.text('Восстановить из архива'));
      await tester.pumpAndSettle();

      expect(
        repository.relationCommands.single,
        isA<RestoreLongTermRelation>(),
      );

      await confirmUpdate(
        tester,
        repository,
        before: before,
        after: relation(),
      );

      expect(find.textContaining('Архивные связи остаются'), findsNothing);
      expect(find.text('Можно'), findsOneWidget);
      expect(snackBar, findsNothing);
      semantics.dispose();
    });

    for (final (title, source, related, reason) in const [
      (
        'исходный',
        IntentionArchiveState.archived,
        IntentionArchiveState.active,
        'Сначала восстановите исходное намерение, затем восстановите эту '
            'связь.',
      ),
      (
        'связанный',
        IntentionArchiveState.active,
        IntentionArchiveState.archived,
        'Сначала восстановите связанное намерение, затем восстановите эту '
            'связь.',
      ),
      (
        'оба',
        IntentionArchiveState.archived,
        IntentionArchiveState.archived,
        'Сначала восстановите исходное и связанное намерения, затем '
            'восстановите эту связь.',
      ),
    ]) {
      testWidgets('восстановление остаётся в меню с причиной, пока архивирован '
          '$title участник', (tester) async {
        final semantics = tester.ensureSemantics();
        final repository = await openPanel(
          tester,
          relation(
            scope: RelationScope.archived,
            sourceArchiveState: source,
            relatedArchiveState: related,
          ),
        );

        await openMenu(tester);
        expect(find.text('Восстановить из архива'), findsOneWidget);
        expect(find.text(reason), findsOneWidget);

        await tester.tap(find.text('Восстановить из архива'));
        await tester.pumpAndSettle();

        expect(repository.relationCommands, isEmpty);
        expect(find.text(reason), findsOneWidget);
        semantics.dispose();
      });
    }

    testWidgets('удаление остаётся в меню с причиной, пока связь входит в путь '
        'дневного выбора', (tester) async {
      final semantics = tester.ensureSemantics();
      final repository = await openPanel(
        tester,
        relation(
          permissions:
              const LongTermRelationPermissions.referencedByDailyPath(),
        ),
      );

      await openMenu(tester);
      expect(
        find.text(
          'Связь используется в сохранённом дневном пути, поэтому удалить её '
          'нельзя.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Удалить'));
      await tester.pumpAndSettle();

      expect(find.text('Удалить связь?'), findsNothing);
      expect(repository.relationCommands, isEmpty);
      semantics.dispose();
    });

    testWidgets('пока операция выполняется, пункты просят дождаться её '
        'окончания', (tester) async {
      final semantics = tester.ensureSemantics();
      final repository = await openPanel(tester, relation());
      await tester.tap(find.text('P1'));
      await tester.pump();

      await openMenu(tester);
      expect(
        find.text('Дождитесь окончания текущего изменения'),
        findsNWidgets(2),
      );
      await tester.tap(find.text('Архивировать'));
      await tester.pumpAndSettle();

      expect(repository.relationCommands, hasLength(1));
      semantics.dispose();
    });

    testWidgets('удаление спрашивает подтверждение с названием связи и '
        'необратимостью, а отмена не отправляет команду', (tester) async {
      final semantics = tester.ensureSemantics();
      final repository = await openPanel(tester, relation());

      await choose(tester, 'Удалить');

      expect(find.text('Удалить связь?'), findsOneWidget);
      expect(find.textContaining(phrase), findsOneWidget);
      expect(find.textContaining('безвозвратно удалена'), findsOneWidget);

      await tester.tap(find.text('Отмена'));
      await tester.pumpAndSettle();

      expect(repository.relationCommands, isEmpty);
      expect(find.text('Параметры связи'), findsNothing);
      expect(find.text('много ходить').hitTestable(), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('зависимость, появившаяся при открытом подтверждении, не даёт '
        'отправить удаление', (tester) async {
      final semantics = tester.ensureSemantics();
      final repository = await openPanel(tester, relation());

      await choose(tester, 'Удалить');
      repository
          .watchAt(0)
          .emitDetails(
            relation(
              permissions:
                  const LongTermRelationPermissions.referencedByDailyPath(),
            ),
            revision: const TestGraphRevision(2),
          );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Удалить'));
      await tester.pumpAndSettle();

      expect(repository.relationCommands, isEmpty);
      expect(find.text('много ходить').hitTestable(), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('подтверждённое удаление закрывает панель, а сообщение '
        'называет удаление', (tester) async {
      final semantics = tester.ensureSemantics();
      final details = relation();
      final repository = await openPanel(tester, details);

      await choose(tester, 'Удалить');
      await tester.tap(find.text('Удалить'));
      await tester.pump();

      expect(repository.relationCommands.single, isA<DeleteLongTermRelation>());

      repository.completeRelationDelete(
        0,
        relation: details.relation,
        revision: const TestGraphRevision(2),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('Открыть').hitTestable(), findsOneWidget);
      expect(find.textContaining('Связь удалена.'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('удаление закрывает только панель, принявшую команду', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final details = relation();
      final repository = await openPanel(tester, details);

      await choose(tester, 'Удалить');
      await tester.tap(find.text('Удалить'));
      await tester.pump();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Открыть'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      repository.relationWatches.last.emitDetails(details, revision: revision);
      await tester.pumpAndSettle();

      repository.completeRelationDelete(
        0,
        relation: details.relation,
        revision: const TestGraphRevision(2),
      );
      await tester.pumpAndSettle();

      expect(find.text('Эта связь больше не существует.'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('отказ удаления остаётся в панели с данными, а повтор '
        'закрывает панель до позднего снимка', (tester) async {
      final semantics = tester.ensureSemantics();
      final details = relation();
      final repository = await openPanel(tester, details);

      await choose(tester, 'Удалить');
      await tester.tap(find.text('Удалить'));
      await tester.pump();
      repository.failRelationCommand(
        0,
        const LongTermRelationUnavailableFailure(),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Не удалось удалить связь. Повторите попытку.'),
        findsOneWidget,
      );
      expect(find.text('много ходить').hitTestable(), findsOneWidget);

      await tester.tap(find.text('Повторить'));
      await tester.pump();
      repository.completeRelationDelete(
        1,
        relation: details.relation,
        revision: const TestGraphRevision(2),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('Открыть').hitTestable(), findsOneWidget);
      expect(repository.relationCommands, hasLength(2));
      expect(
        repository.relationCommands,
        everyElement(isA<DeleteLongTermRelation>()),
      );

      repository
          .watchAt(0)
          .emitDetails(details, revision: const TestGraphRevision(3));
      await tester.pump();
      expect(find.text('много ходить'), findsNothing);
      semantics.dispose();
    });

    testWidgets('устранимый отказ архивирования остаётся в панели, а повтор '
        'отправляет ту же команду', (tester) async {
      final semantics = tester.ensureSemantics();
      final repository = await openPanel(tester, relation());

      await choose(tester, 'Архивировать');
      repository.failRelationCommand(
        0,
        const LongTermRelationUnavailableFailure(),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Не удалось архивировать связь. Повторите попытку.'),
        findsOneWidget,
      );

      await tester.tap(find.text('Повторить'));
      await tester.pump();

      expect(repository.relationCommands, hasLength(2));
      expect(
        repository.relationCommands,
        everyElement(isA<ArchiveLongTermRelation>()),
      );
      expect(
        find.text('Не удалось архивировать связь. Повторите попытку.'),
        findsNothing,
      );
      semantics.dispose();
    });

    testWidgets('отказ восстановления из-за участника объясняется в панели '
        'без повтора', (tester) async {
      final semantics = tester.ensureSemantics();
      final details = relation(scope: RelationScope.archived);
      final repository = await openPanel(tester, details);

      await choose(tester, 'Восстановить из архива');
      repository.failRelationCommand(
        0,
        LongTermRelationParticipantArchivedFailure(
          role: RelationParticipantRole.related,
          intentionId: details.related.id,
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Сначала восстановите связанное намерение, затем восстановите эту '
          'связь.',
        ),
        findsOneWidget,
      );
      expect(find.text('Повторить'), findsNothing);
      expect(find.textContaining('Архивные связи остаются'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('поздний выбор отбрасывается, если панель уже перекрыта', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final repository = await openPanel(tester, relation());

      await openMenu(tester);
      await tester.tap(find.text('Архивировать'));
      unawaited(
        Navigator.of(
          tester.element(find.text('Открыть')),
          rootNavigator: true,
        ).push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('Над панелью')),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Над панелью'), findsOneWidget);
      expect(repository.relationCommands, isEmpty);
      semantics.dispose();
    });

    testWidgets('меню закрывается, когда связи больше нет', (tester) async {
      final semantics = tester.ensureSemantics();
      final repository = await openPanel(tester, relation());

      await openMenu(tester);
      repository.watchAt(0).emitMissing(revision: const TestGraphRevision(2));
      await tester.pumpAndSettle();

      expect(find.text('Архивировать'), findsNothing);
      expect(find.text('Эта связь больше не существует.'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('при изменении описания кнопки параметров нет', (tester) async {
      final semantics = tester.ensureSemantics();
      await openPanel(tester, relation());
      await tester.tap(find.text('Добавить описание'));
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel('Параметры связи'), findsNothing);
      semantics.dispose();
    });
  });

  group('размер панели', () {
    const screen = Size(390, 844);
    const statusBar = 47.0;
    const saved = 'Хотя бы раз в неделю';
    const expand = 'Раскрыть панель связи';
    const collapse = 'Свернуть панель связи';
    const full = Rect.fromLTRB(0, statusBar, 390, 844);

    Future<void> openLoaded(WidgetTester tester) async {
      tester.view
        ..devicePixelRatio = 1
        ..physicalSize = screen
        ..padding = const FakeViewPadding(top: statusBar);
      addTearDown(tester.view.reset);
      final repository = await _openSheet(tester);
      repository
          .watchAt(0)
          .emitDetails(
            testRelationDetails(
              relationId: relationId,
              sourceId: testIntentionId(1),
              relatedId: testIntentionId(2),
              description: saved,
            ),
            revision: revision,
          );
      await tester.pumpAndSettle();
    }

    Future<void> openDescription(WidgetTester tester) async {
      await tester.tap(find.text(saved));
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byType(Sheet)), full);
      expect(find.text('Сохранить'), findsOneWidget);
    }

    Future<void> leaveDescription(WidgetTester tester) async {
      await tester.tap(find.bySemanticsLabel('Назад к связи'));
      await tester.pumpAndSettle();
      expect(find.text('Сохранить'), findsNothing);
    }

    testWidgets('ручка раскрывает панель на весь экран под строкой состояния, '
        'даже когда связь помещается, а следующее нажатие возвращает '
        'компактный размер', (tester) async {
      final semantics = tester.ensureSemantics();
      await openLoaded(tester);
      final compact = tester.getRect(find.byType(Sheet));
      expect(compact.top, greaterThan(statusBar));
      expect(find.bySemanticsLabel(collapse), findsNothing);

      await tester.tap(find.bySemanticsLabel(expand));
      await tester.pumpAndSettle();

      expect(tester.getRect(find.byType(Sheet)), full);
      expect(find.bySemanticsLabel(expand), findsNothing);

      await tester.tap(find.bySemanticsLabel(collapse));
      await tester.pumpAndSettle();

      expect(tester.getRect(find.byType(Sheet)), compact);
      expect(find.bySemanticsLabel(expand), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('выход из изменения описания возвращает раскрытую панель с '
        'ручкой вместо полосы', (tester) async {
      final semantics = tester.ensureSemantics();
      await openLoaded(tester);
      await tester.tap(find.bySemanticsLabel(expand));
      await tester.pumpAndSettle();

      await openDescription(tester);
      expect(find.bySemanticsLabel(collapse), findsNothing);
      await leaveDescription(tester);

      expect(tester.getRect(find.byType(Sheet)), full);
      expect(find.bySemanticsLabel(collapse), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('изменение, открытое из компактного размера, возвращает '
        'компактный размер', (tester) async {
      final semantics = tester.ensureSemantics();
      await openLoaded(tester);
      final compact = tester.getRect(find.byType(Sheet));

      await openDescription(tester);
      await leaveDescription(tester);

      expect(tester.getRect(find.byType(Sheet)), compact);
      expect(find.bySemanticsLabel(expand), findsOneWidget);
      semantics.dispose();
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
