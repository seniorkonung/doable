import 'package:doable/src/action/application/action_details.dart';
import 'package:doable/src/action/domain/action_path.dart';
import 'package:doable/src/action/presentation/path/path_state.dart';
import 'package:doable/src/action/presentation/path_start/path_start_picker_page.dart';
import 'package:doable/src/app/navigation/app_navigation_bar.dart';
import 'package:doable/src/app/routing/app_router.dart';
import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/design_system/components/relation_head.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/presentation/details/intention_details_page.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_command.dart';
import 'package:doable/src/long_term_relation/presentation/batch_picker/relation_batch_picker_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../../support/action_seed.dart';
import '../../../support/graph_seed.dart';
import '../../../support/in_memory_diagnostics_sink.dart';
import '../../../support/path_screen_controls.dart';

/// Отказывает чтению участка пути, пока включён.
final class _PathReadFailure extends LocalDatabaseConnectionObserver {
  Object? failure;

  @override
  void beforeStatement(LocalDatabaseSqlStatement statement) {
    final error = failure;
    if (error != null &&
        statement.operation == LocalDatabaseSqlOperation.select &&
        statement.statements.single.contains('FROM long_term_relations')) {
      throw error;
    }
  }
}

ActionPath _path(List<int> intentions) =>
    ActionPath([for (final number in intentions) seedIntentionId(number)]);

void main() {
  late sqlite.Database raw;
  late AppDatabase database;
  late DriftPersonalGraphRepository repository;
  late AppRouter router;
  late _PathReadFailure readFailure;

  setUp(() async {
    readFailure = _PathReadFailure();
    database = AppDatabase(
      observeConfiguredLocalDatabaseConnection(
        openInMemoryLocalDatabase(setup: (db) => raw = db),
        readFailure,
      ),
    );
    await database.open();
    repository = DriftPersonalGraphRepository(
      database,
      UuidV7IntentionIdGenerator(),
      DateTime.now,
      InMemoryDiagnosticsSink(),
    );
    // 1 «Быть здоровым» —нужно→ 2 «Много ходить» —можно→ 3 «Покупать обувь»;
    // 4 «Высыпаться» без связей.
    seedRawGraph(raw, () {
      for (final (number, title) in [
        (1, 'Быть здоровым'),
        (2, 'Много ходить'),
        (3, 'Покупать обувь'),
        (4, 'Высыпаться'),
      ]) {
        seedIntention(raw, seedUuid(number), title);
      }
      seedRelation(raw, seedUuid(101), seedUuid(1), seedUuid(2));
      seedRelation(raw, seedUuid(102), seedUuid(2), seedUuid(3));
      raw.execute(
        'UPDATE long_term_relations SET type = ?, priority = 2 WHERE id = ?',
        [LongTermRelationType.can.name, seedUuid(102)],
      );
    });
    router = AppRouter();
  });

  tearDown(() async {
    router.dispose();
    await database.close();
  });

  /// Сохранённое действие с путём [intentions] после изменений графа
  /// [change] — так экран открывает панель.
  Future<ExistingActionPathPurpose> savedPath(
    WidgetTester tester,
    List<int> intentions, {
    void Function()? change,
  }) async {
    seedRawGraph(raw, () {
      seedAction(
        raw,
        id: seedUuid(201),
        path: [for (final number in intentions) seedUuid(number)],
      );
      change?.call();
    });
    final read = await tester.runAsync(
      () => repository.watchAction(seedActionId(201)).first,
    );
    return ExistingActionPathPurpose((read! as ActionReadSuccess).value.value!);
  }

  /// Связи графа, исходящие из намерения [source], в порядке создания.
  List<(String, String)> relationsFrom(int source) => [
    for (final row in raw.select(
      'SELECT related_intention_id, type FROM long_term_relations '
      'WHERE source_intention_id = ? ORDER BY creation_sequence',
      [seedUuid(source)],
    ))
      (row['related_intention_id'] as String, row['type'] as String),
  ];

  /// Отмечает в открытом поиске участника намерения [titles] по порядку и
  /// добавляет связи.
  Future<void> addRelations(WidgetTester tester, List<String> titles) async {
    for (final title in titles) {
      await tester.tap(find.text(title));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.textContaining(RegExp(r'^Добавить \d+ связ')));
    await settlePathScreen(tester);
  }

  /// Путь действия в хранилище.
  List<String> storedPath() => [
    for (final row in raw.select(
      'SELECT intention_id FROM action_path_items WHERE action_id = ? '
      'ORDER BY position',
      [seedUuid(201)],
    ))
      row['intention_id'] as String,
  ];

  GraphCommandCoordinator coordinator(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(pathScreen))
          .read(graphCommandCoordinatorProvider.notifier);

  LongTermRelationId relationId(int number) => (LongTermRelationId.decode(
    seedUuid(number),
  ) as LongTermRelationIdDecodingSuccess).id;

  testWidgets('архивная связь сокращает открытый путь и исключает кандидата', (
    tester,
  ) async {
    await openPathScreen(
      tester,
      router: router,
      repository: repository,
      purpose: NewActionPathPurpose(_path([1, 2, 3])),
    );
    final start = coordinator(tester).acceptRelationArchive(
      ArchiveLongTermRelation(relationId(102)),
    ) as LongTermRelationCommandAccepted;
    final completion = await tester.runAsync(() => start.future);
    expect(completion!.isFailure, isFalse);
    await settlePathScreen(tester);
    expect(find.text('Много ходить'), findsOneWidget);
    expect(find.text('Покупать обувь'), findsNothing);
    expect(isPathSaveEnabled(tester), isTrue);
    await tapPathBack(tester);
    expect(find.text('Отменить изменения?'), findsOneWidget);
  });

  testWidgets('архивирование корня очищает путь', (tester) async {
    await openPathScreen(
      tester,
      router: router,
      repository: repository,
      purpose: NewActionPathPurpose(_path([1, 2])),
    );
    final start = coordinator(tester).acceptExisting(
      ArchiveIntention(seedIntentionId(1)),
      presentationTitle: 'Быть здоровым',
    ) as IntentionCommandAccepted;
    final completion = await tester.runAsync(() => start.future);
    expect(completion!.isFailure, isFalse);
    await settlePathScreen(tester);
    expect(find.text('Выберите причину'), findsOneWidget);
    expect(isPathSaveEnabled(tester), isFalse);
    await tapPathBack(tester);
    expect(find.text('Отменить изменения?'), findsOneWidget);
  });

  testWidgets(
    'изменения названия и связи обновляют путь без изменения состава',
    (tester) async {
      await openPathScreen(
        tester,
        router: router,
        repository: repository,
        purpose: NewActionPathPurpose(_path([1, 2])),
      );
      final rename = coordinator(tester).acceptExisting(
        UpdateIntention(
          id: seedIntentionId(2),
          title: 'Ходить пешком',
          description: null,
        ),
        presentationTitle: 'Много ходить',
      ) as IntentionCommandAccepted;
      expect((await tester.runAsync(() => rename.future))!.isFailure, isFalse);
      final update = coordinator(tester).acceptRelationUpdate(
        UpdateLongTermRelation(
          relationId: relationId(101),
          patch: const LongTermRelationPatch(
            type: LongTermRelationFieldSet(LongTermRelationType.can),
            priority: LongTermRelationFieldSet(RelationPriority.p3),
          ),
        ),
      ) as LongTermRelationCommandAccepted;
      expect((await tester.runAsync(() => update.future))!.isFailure, isFalse);
      await settlePathScreen(tester);
      expect(find.text('Ходить пешком'), findsOneWidget);
      expect(find.text('Много ходить'), findsNothing);
      expect(find.text('Можно'), findsWidgets);
      expect(
        find.bySemanticsLabel(
          'Связь Можно. Быть здоровым, Ходить пешком. Приоритет P3',
        ),
        findsOneWidget,
      );
      expect(isPathSaveEnabled(tester), isFalse);
    },
  );

  testWidgets(
    'пустой путь предлагает выбрать причину, а «Назад» сразу возвращает',
    (tester) async {
      final result = await openPathScreen(
        tester,
        router: router,
        repository: repository,
      );

      expect(find.text('Путь'), findsOneWidget);
      expect(find.byType(AppNavigationBar), findsNothing);
      expect(find.text('Выберите причину'), findsOneWidget);
      expect(
        find.textContaining('Начните с цели, ради которой делается действие'),
        findsOneWidget,
      );
      expect(find.text('Новое действие'), findsOneWidget);
      expect(isPathSaveEnabled(tester), isFalse);

      await tapPathBack(tester);
      expect(pathScreen, findsNothing);
      expect(await result, isNull);
    },
  );

  testWidgets(
    'путь идёт сверху вниз со связями и замыкается названием действия',
    (tester) async {
      await openPathScreen(
        tester,
        router: router,
        repository: repository,
        purpose: await savedPath(tester, [1, 2, 3]),
        actionTitle: 'Силовая тренировка',
      );

      expect(find.text('Изменить путь'), findsOneWidget);
      final rows = [
        'Быть здоровым',
        'Нужно',
        'Много ходить',
        'Можно',
        'Покупать обувь',
        'Силовая тренировка',
      ].map((text) => tester.getTopLeft(find.text(text).first).dy).toList();
      expect(rows, orderedEquals([...rows]..sort()));
      expect(
        find.text('Нажмите на намерение, чтобы закончить путь на нём.'),
        findsOneWidget,
      );
      expect(isPathSaveEnabled(tester), isFalse);
    },
  );

  testWidgets(
    'промежуточное намерение заканчивает путь, а «Сохранить» возвращает его',
    (tester) async {
      final result = await openPathScreen(
        tester,
        router: router,
        repository: repository,
        purpose: NewActionPathPurpose(_path([1, 2, 3])),
      );

      // Конечное намерение — простой текст.
      await tester.tap(find.text('Покупать обувь'));
      await tester.pumpAndSettle();
      expect(find.text('Покупать обувь'), findsOneWidget);
      expect(isPathSaveEnabled(tester), isFalse);

      await tester.tap(find.text('Много ходить'));
      await tester.pumpAndSettle();
      expect(find.text('Покупать обувь'), findsOneWidget);
      expect(isPathSaveEnabled(tester), isTrue);

      await tester.tap(pathSave);
      await tester.pumpAndSettle();
      expect(pathScreen, findsNothing);
      expect((await result)!.intentions, _path([1, 2]).intentions);
      // Сокращение не меняет граф.
      expect(
        raw.select('SELECT 1 FROM long_term_relations WHERE id = ?', [
          seedUuid(102),
        ]),
        hasLength(1),
      );
    },
  );

  testWidgets(
    'корень меняется в поиске начала пути, а закрытие поиска путь не меняет',
    (tester) async {
      await openPathScreen(
        tester,
        router: router,
        repository: repository,
        purpose: NewActionPathPurpose(_path([1, 2])),
      );

      await tester.tap(find.text('Быть здоровым'));
      await tester.pumpAndSettle();
      expect(find.byType(PathStartPickerPage), findsOneWidget);
      expect(find.text('Новое действие: с чего начинается путь'), findsOne);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(PathStartPickerPage), findsNothing);
      expect(find.text('Много ходить'), findsOneWidget);
      expect(isPathSaveEnabled(tester), isFalse);

      await tester.tap(find.text('Быть здоровым'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Высыпаться'));
      await settlePathScreen(tester);
      expect(find.byType(PathStartPickerPage), findsNothing);
      expect(find.text('Высыпаться'), findsOneWidget);
      expect(find.text('Быть здоровым'), findsNothing);
      expect(find.text('Много ходить'), findsNothing);
      expect(isPathSaveEnabled(tester), isTrue);
    },
  );

  testWidgets(
    'выбор текущего корня в поиске начала пути сокращает путь до него',
    (tester) async {
      final result = await openPathScreen(
        tester,
        router: router,
        repository: repository,
        purpose: NewActionPathPurpose(_path([1, 2])),
      );
      expect(isPathSaveEnabled(tester), isFalse);

      await tester.tap(find.text('Быть здоровым'));
      await tester.pumpAndSettle();
      final root = find.descendant(
        of: find.byType(PathStartPickerPage),
        matching: find.text('Быть здоровым'),
      );
      expect(root, findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(PathStartPickerPage),
          matching: find.text('Сейчас в начале пути'),
        ),
        findsOneWidget,
      );
      await tester.tap(root);
      await settlePathScreen(tester);
      expect(find.byType(PathStartPickerPage), findsNothing);
      expect(isPathSaveEnabled(tester), isTrue);

      await tester.tap(pathSave);
      await tester.pumpAndSettle();
      expect((await result)!.intentions, _path([1]).intentions);
      expect(relationsFrom(1), [(seedUuid(2), LongTermRelationType.need.name)]);
    },
  );

  testWidgets(
    'кандидат продолжает путь и возврат исходного пути отключает сохранение',
    (tester) async {
      await openPathScreen(
        tester,
        router: router,
        repository: repository,
        purpose: NewActionPathPurpose(_path([1, 2, 3])),
      );
      await tester.tap(find.text('Много ходить'));
      await settlePathScreen(tester);
      expect(isPathSaveEnabled(tester), isTrue);
      await tester.tap(find.text('Покупать обувь'));
      await settlePathScreen(tester);
      expect(isPathSaveEnabled(tester), isFalse);
      expect(find.text('Пока ничего не нужно'), findsOneWidget);
    },
  );

  testWidgets(
    'половины показывают числа, выбирают непустую и доступны пустые',
    (tester) async {
      await openPathScreen(
        tester,
        router: router,
        repository: repository,
        purpose: NewActionPathPurpose(_path([1, 2])),
      );
      expect(find.text('Покупать обувь'), findsOneWidget);
      expect(find.text('0'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
      await tester.tap(find.text('Нужно').last);
      await settlePathScreen(tester);
      expect(find.text('Пока ничего не нужно'), findsOneWidget);
      expect(find.text('Покупать обувь'), findsNothing);
      await tester.tap(find.text('Можно').last);
      await settlePathScreen(tester);
      expect(find.text('Покупать обувь'), findsOneWidget);
      await tester.tap(find.text('Покупать обувь'));
      await settlePathScreen(tester);
      expect(find.text('Пока ничего не нужно'), findsOneWidget);
      await tester.tap(find.text('Можно').last);
      await settlePathScreen(tester);
      expect(find.text('Пока нечего использовать'), findsOneWidget);
    },
  );

  testWidgets('стрелка кандидата открывает намерение без изменения пути', (
    tester,
  ) async {
    await openPathScreen(
      tester,
      router: router,
      repository: repository,
      purpose: NewActionPathPurpose(_path([1])),
    );
    await tester.tap(
      find.byTooltip('Открыть страницу намерения «Много ходить»'),
    );
    await tester.pumpAndSettle();
    expect(find.byType(IntentionDetailsPage), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(isPathSaveEnabled(tester), isFalse);
    expect(find.text('Много ходить'), findsOneWidget);
  });

  testWidgets('следующая порция кандидатов загружается при прокрутке', (
    tester,
  ) async {
    seedRawGraph(raw, () {
      for (var i = 10; i < 61; i++) {
        seedIntention(raw, seedUuid(i), 'Кандидат $i');
        seedRelation(raw, seedUuid(200 + i), seedUuid(1), seedUuid(i));
      }
    });
    await openPathScreen(
      tester,
      router: router,
      repository: repository,
      purpose: NewActionPathPurpose(_path([1])),
    );
    expect(find.text('52'), findsOneWidget);
    expect(find.text('Кандидат 60'), findsNothing);
    await tester.drag(
      find.byType(SingleChildScrollView).first,
      const Offset(0, -10000),
    );
    await settlePathScreen(tester);
    expect(find.text('Кандидат 60'), findsOneWidget);
  });

  testWidgets(
    'отказ чтения половины не подменяется пустым состоянием и повторяется',
    (tester) async {
      await openPathScreen(
        tester,
        router: router,
        repository: repository,
        purpose: NewActionPathPurpose(_path([1, 2])),
      );
      readFailure.failure = sqlite.SqliteException(
        extendedResultCode: sqlite.SqlError.SQLITE_BUSY,
        message: 'database is locked',
      );
      await tester.tap(find.text('Нужно').last);
      await settlePathScreen(tester);
      expect(
        find.text(
          'Не удалось загрузить следующие намерения. Повторите попытку.',
        ),
        findsOneWidget,
      );
      expect(find.text('Пока ничего не нужно'), findsNothing);
      expect(find.text('0'), findsNothing);
      readFailure.failure = null;
      await tester.tap(find.text('Повторить'));
      await settlePathScreen(tester);
      expect(find.text('Пока ничего не нужно'), findsOneWidget);
    },
  );

  testWidgets(
    'сокращение пути заново выбирает половину и показывает кандидата по приоритету',
    (tester) async {
      seedRawGraph(raw, () {
        seedRelation(raw, seedUuid(103), seedUuid(2), seedUuid(4));
        raw.execute(
          'UPDATE long_term_relations SET type = ?, priority = 1 WHERE id = ?',
          [LongTermRelationType.need.name, seedUuid(102)],
        );
        raw.execute(
          'UPDATE long_term_relations SET priority = 2 WHERE id = ?',
          [seedUuid(103)],
        );
      });
      await openPathScreen(
        tester,
        router: router,
        repository: repository,
        purpose: NewActionPathPurpose(_path([1, 2, 3])),
      );
      await tester.tap(find.text('Можно').last);
      await settlePathScreen(tester);
      await tester.tap(find.text('Много ходить'));
      await settlePathScreen(tester);
      expect(
        tester.getTopLeft(find.text('Покупать обувь')).dy,
        lessThan(tester.getTopLeft(find.text('Высыпаться')).dy),
      );
      expect(find.text('Пока нечего использовать'), findsNothing);
    },
  );

  testWidgets(
    'после выбора кандидата отказ оставляет путь и повтор выбирает непустую половину',
    (tester) async {
      await openPathScreen(
        tester,
        router: router,
        repository: repository,
        purpose: NewActionPathPurpose(_path([1])),
      );
      readFailure.failure = sqlite.SqliteException(
        extendedResultCode: sqlite.SqlError.SQLITE_BUSY,
        message: 'database is locked',
      );
      await tester.tap(find.text('Много ходить'));
      await settlePathScreen(tester);
      expect(find.text('Быть здоровым'), findsOneWidget);
      expect(find.text('Много ходить'), findsOneWidget);
      expect(
        find.text(
          'Не удалось загрузить следующие намерения. Повторите попытку.',
        ),
        findsOneWidget,
      );
      readFailure.failure = null;
      await tester.tap(find.text('Повторить'));
      await settlePathScreen(tester);
      expect(find.text('Покупать обувь'), findsOneWidget);
    },
  );

  testWidgets('стрелка намерения открывает его страницу поверх экрана', (
    tester,
  ) async {
    await openPathScreen(
      tester,
      router: router,
      repository: repository,
      purpose: NewActionPathPurpose(_path([1, 2])),
    );

    await tester.tap(
      find.byTooltip('Открыть страницу намерения «Много ходить»'),
    );
    await tester.pumpAndSettle();
    expect(find.byType(IntentionDetailsPage), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(IntentionDetailsPage), findsNothing);
    expect(find.text('Быть здоровым'), findsOneWidget);
    expect(find.text('Много ходить'), findsOneWidget);
  });

  testWidgets('нажатие на связь пути открывает её подробный просмотр', (
    tester,
  ) async {
    await openPathScreen(
      tester,
      router: router,
      repository: repository,
      purpose: NewActionPathPurpose(_path([1, 2])),
    );

    await tester.tap(find.text('Нужно').first);
    await settlePathScreen(tester);
    expect(find.byType(RelationHead), findsOneWidget);
  });

  testWidgets(
    '«Назад» с изменённым путём спрашивает, а «Отменить» возвращает без пути',
    (tester) async {
      final result = await openPathScreen(
        tester,
        router: router,
        repository: repository,
        purpose: NewActionPathPurpose(_path([1, 2])),
      );
      await tester.tap(find.text('Быть здоровым'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Высыпаться'));
      await settlePathScreen(tester);

      await tapPathBack(tester);
      expect(find.text('Отменить изменения?'), findsOneWidget);
      expect(find.text('Изменения пути не сохранятся.'), findsOneWidget);
      await tester.tap(find.text('Продолжить правку'));
      await tester.pumpAndSettle();
      expect(pathScreen, findsOneWidget);
      expect(find.text('Высыпаться'), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Отменить изменения?'), findsOneWidget);
      await tester.tap(find.text('Отменить'));
      await tester.pumpAndSettle();
      expect(pathScreen, findsNothing);
      expect(await result, isNull);
    },
  );

  testWidgets('отказ чтения пути не выглядит пустым путём и повторяется', (
    tester,
  ) async {
    readFailure.failure = sqlite.SqliteException(
      extendedResultCode: sqlite.SqlError.SQLITE_BUSY,
      message: 'database is locked',
    );
    await openPathScreen(
      tester,
      router: router,
      repository: repository,
      purpose: NewActionPathPurpose(_path([1])),
    );

    expect(
      find.text('Не удалось загрузить путь. Повторите попытку.'),
      findsOne,
    );
    expect(find.text('Выберите причину'), findsNothing);
    expect(isPathSaveEnabled(tester), isFalse);

    readFailure.failure = null;
    await tester.tap(find.text('Повторить'));
    await settlePathScreen(tester);
    expect(find.text('Быть здоровым'), findsOneWidget);
  });

  testWidgets(
    '«Сохранить» заменяет путь действия и закрывает экран с новым путём',
    (tester) async {
      final result = await openPathScreen(
        tester,
        router: router,
        repository: repository,
        purpose: await savedPath(tester, [1, 2]),
      );
      await tester.tap(find.text('Покупать обувь'));
      await settlePathScreen(tester);

      await tester.tap(pathSave);
      await settlePathScreen(tester);
      expect(pathScreen, findsNothing);
      expect((await result)!.intentions, _path([1, 2, 3]).intentions);
      expect(storedPath(), [seedUuid(1), seedUuid(2), seedUuid(3)]);
    },
  );

  testWidgets(
    'отказ замены остаётся на экране с тем же путём, а путь действия прежний',
    (tester) async {
      await openPathScreen(
        tester,
        router: router,
        repository: repository,
        purpose: await savedPath(tester, [1, 2, 3]),
      );
      await tester.tap(find.text('Много ходить'));
      await settlePathScreen(tester);
      // Связь архивирована, пока экран открыт.
      seedRawGraph(
        raw,
        () => raw.execute(
          'UPDATE long_term_relations SET is_archived = 1 WHERE id = ?',
          [seedUuid(101)],
        ),
      );

      await tester.tap(pathSave);
      await settlePathScreen(tester);
      expect(pathScreen, findsOneWidget);
      expect(
        find.text(
          'Путь больше не совпадает с графом. Проверьте путь и попробуйте снова.',
        ),
        findsOneWidget,
      );
      expect(find.text('Быть здоровым'), findsOneWidget);
      expect(find.text('Много ходить'), findsOneWidget);
      expect(storedPath(), [seedUuid(1), seedUuid(2), seedUuid(3)]);
    },
  );

  testWidgets(
    'путь с разрывом открывается с первого целого участка, и его можно '
    'сохранить сразу',
    (tester) async {
      final result = await openPathScreen(
        tester,
        router: router,
        repository: repository,
        purpose: await savedPath(
          tester,
          [1, 2, 3],
          change: () => raw.execute(
            'UPDATE long_term_relations SET is_archived = 1 WHERE id = ?',
            [seedUuid(102)],
          ),
        ),
      );

      expect(find.text('Много ходить'), findsOneWidget);
      expect(find.text('Покупать обувь'), findsNothing);
      expect(isPathSaveEnabled(tester), isTrue);
      expect(storedPath(), [seedUuid(1), seedUuid(2), seedUuid(3)]);

      await tapPathBack(tester);
      expect(find.text('Отменить изменения?'), findsOneWidget);
      await tester.tap(find.text('Отменить'));
      await tester.pumpAndSettle();
      expect(await result, isNull);
      expect(storedPath(), [seedUuid(1), seedUuid(2), seedUuid(3)]);
    },
  );

  testWidgets(
    'архивный корень сдвигает корень участка на следующее намерение',
    (tester) async {
      await openPathScreen(
        tester,
        router: router,
        repository: repository,
        purpose: await savedPath(
          tester,
          [1, 2, 3],
          change: () {
            raw.execute(
              'UPDATE long_term_relations SET is_archived = 1 '
              'WHERE id = ?',
              [seedUuid(101)],
            );
            raw.execute('UPDATE intentions SET is_archived = 1 WHERE id = ?', [
              seedUuid(1),
            ]);
          },
        ),
      );

      expect(find.text('Быть здоровым'), findsNothing);
      expect(find.text('Много ходить'), findsOneWidget);
      expect(find.text('Покупать обувь'), findsOneWidget);
      expect(isPathSaveEnabled(tester), isTrue);
    },
  );

  testWidgets('без актуальных намерений путь на экране пуст', (tester) async {
    await openPathScreen(
      tester,
      router: router,
      repository: repository,
      purpose: await savedPath(
        tester,
        [1, 2],
        change: () {
          raw.execute('UPDATE long_term_relations SET is_archived = 1');
          raw.execute(
            'UPDATE intentions SET is_archived = 1 WHERE id IN '
            '(?, ?)',
            [seedUuid(1), seedUuid(2)],
          );
        },
      ),
    );

    expect(find.text('Выберите причину'), findsOneWidget);
    expect(find.text('Быть здоровым'), findsNothing);
    expect(isPathSaveEnabled(tester), isFalse);
  });

  testWidgets(
    '«Добавить» создаёт связи последнего намерения, а их кандидаты стоят '
    'последними с отметкой «Новое»',
    (tester) async {
      await openPathScreen(
        tester,
        router: router,
        repository: repository,
        purpose: NewActionPathPurpose(_path([1])),
      );
      expect(find.text('Много ходить'), findsOneWidget);

      await tester.tap(find.text('Добавить'));
      await tester.pumpAndSettle();
      expect(find.byType(RelationBatchPickerPage), findsOneWidget);
      await tester.tap(find.text('Добавить в "Нужно"'));
      await tester.pumpAndSettle();
      expect(find.text('Быть здоровым'), findsOneWidget);
      expect(find.text('Последнее намерение пути'), findsOneWidget);
      await tester.tap(find.text('Вернуться к списку'));
      await tester.pumpAndSettle();
      await addRelations(tester, ['Высыпаться', 'Покупать обувь']);

      expect(find.byType(RelationBatchPickerPage), findsNothing);
      expect(relationsFrom(1), [
        (seedUuid(2), 'need'),
        (seedUuid(4), 'need'),
        (seedUuid(3), 'need'),
      ]);
      // Путь прежний, а связи не входят в него сами.
      expect(isPathSaveEnabled(tester), isFalse);
      expect(find.text('3'), findsOneWidget);
      final rows = [
        'Много ходить',
        'Высыпаться',
        'Покупать обувь',
      ].map((text) => tester.getTopLeft(find.text(text)).dy).toList();
      expect(rows, orderedEquals([...rows]..sort()));
      expect(find.text('Новое'), findsNWidgets(2));
      expect(
        find.bySemanticsLabel(RegExp('«Покупать обувь».*Новое')),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(RegExp('«Много ходить».*Новое')),
        findsNothing,
      );
    },
  );

  testWidgets(
    'открытая половина «Можно» добавляет в «Можно использовать» и остаётся '
    'открытой, а намерение из пути кандидатом не становится',
    (tester) async {
      await openPathScreen(
        tester,
        router: router,
        repository: repository,
        purpose: NewActionPathPurpose(_path([1, 2])),
      );
      expect(find.text('Покупать обувь'), findsOneWidget);

      await tester.tap(find.text('Добавить'));
      await tester.pumpAndSettle();
      expect(find.text('Добавить в "Можно использовать"'), findsOneWidget);
      await addRelations(tester, ['Быть здоровым', 'Высыпаться']);

      expect(relationsFrom(2), [
        (seedUuid(3), 'can'),
        (seedUuid(1), 'can'),
        (seedUuid(4), 'can'),
      ]);
      expect(find.text('Пока ничего не нужно'), findsNothing);
      expect(find.text('Покупать обувь'), findsOneWidget);
      expect(find.text('Высыпаться'), findsOneWidget);
      // «Быть здоровым» стоит только в пути.
      expect(find.text('Быть здоровым'), findsOneWidget);
      expect(find.text('Новое'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
    },
  );

  testWidgets(
    'вопрос при уходе называет добавленные связи и созданное намерение, а '
    '«Отменить» их не удаляет',
    (tester) async {
      final result = await openPathScreen(
        tester,
        router: router,
        repository: repository,
        purpose: NewActionPathPurpose(_path([1])),
      );
      await tester.tap(find.text('Много ходить'));
      await settlePathScreen(tester);

      await tester.tap(find.text('Добавить'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Создать намерение'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('intention-editor-title')),
        'Плавать',
      );
      await tester.tap(find.byKey(const ValueKey('intention-editor-submit')));
      await settlePathScreen(tester);
      await addRelations(tester, ['Высыпаться']);
      expect(find.byType(RelationBatchPickerPage), findsNothing);

      await tapPathBack(tester);
      expect(
        find.text(
          'Изменения пути не сохранятся. Добавленные 2 связи и созданное 1 '
          'намерение останутся.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Отменить'));
      await tester.pumpAndSettle();
      expect(await result, isNull);
      expect(relationsFrom(2), hasLength(3));
      expect(
        raw.select('SELECT 1 FROM intentions WHERE title = ?', ['Плавать']),
        hasLength(1),
      );
    },
  );

  testWidgets(
    'вопрос при уходе называет намерение, созданное в поиске начала пути',
    (tester) async {
      await openPathScreen(
        tester,
        router: router,
        repository: repository,
        purpose: NewActionPathPurpose(_path([1])),
      );
      await tester.tap(find.text('Быть здоровым'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Создать намерение'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('intention-editor-title')),
        'Плавать',
      );
      await tester.tap(find.byKey(const ValueKey('intention-editor-submit')));
      await settlePathScreen(tester);
      expect(find.text('Плавать'), findsOneWidget);

      await tapPathBack(tester);
      expect(
        find.text(
          'Изменения пути не сохранятся. Созданное 1 намерение останется.',
        ),
        findsOneWidget,
      );
    },
  );
}
