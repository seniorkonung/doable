import 'package:doable/src/action/domain/action_path.dart';
import 'package:doable/src/action/presentation/path_start/path_start_picker_page.dart';
import 'package:doable/src/app/navigation/app_navigation_bar.dart';
import 'package:doable/src/app/routing/app_router.dart';
import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/design_system/components/relation_head.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/presentation/details/intention_details_page.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:flutter/material.dart';
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
        originalPath: _path([1, 2, 3]),
        flow: PathStartFlow.editPath,
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
        originalPath: _path([1, 2, 3]),
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
        originalPath: _path([1, 2]),
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
      // Текущий корень поиск не предлагает.
      expect(
        find.descendant(
          of: find.byType(PathStartPickerPage),
          matching: find.text('Быть здоровым'),
        ),
        findsNothing,
      );
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
    'кандидат продолжает путь и возврат исходного пути отключает сохранение',
    (tester) async {
      await openPathScreen(
        tester,
        router: router,
        repository: repository,
        originalPath: _path([1, 2, 3]),
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
        originalPath: _path([1, 2]),
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
      originalPath: _path([1]),
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
      originalPath: _path([1]),
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
        originalPath: _path([1, 2]),
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
        originalPath: _path([1, 2, 3]),
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
        originalPath: _path([1]),
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
      originalPath: _path([1, 2]),
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
      originalPath: _path([1, 2]),
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
        originalPath: _path([1, 2]),
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
      originalPath: _path([1]),
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
}
