import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/main.dart';
import 'package:doable/src/app/app_runtime.dart';
import 'package:doable/src/app/routing/app_router.dart';
import 'package:doable/src/app/routing/app_router_provider.dart';
import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_page.dart';
import 'package:doable/src/intention/presentation/catalog/tag_condition_picker_page.dart';
import 'package:doable/src/intention/presentation/intention_summary_view.dart';
import 'package:doable/src/shared/diagnostics/diagnostics_sink.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../support/app_root_pages.dart';
import '../support/tag_storage_fixture.dart';
import '../support/in_memory_quick_creation_mode_store.dart';

const _health = 301;
const _sport = 302;
const _rest = 303;

/// Связь сохранённого дневного пути: её участники защищены от замены.
const _pathRelation = 101;
const _archivedRelation = 102;
const _activeRelation = 103;
const _dailyChoice = 201;

/// Строка результата: название и строка тегов так, как они показаны.
typedef _Row = (String title, String tags);

void main() {
  for (final locale in const [Locale('ru'), Locale('en')]) {
    final code = locale.languageCode;

    testWidgets(
      'каталог совместно применяет название, обязательные и исключённые теги на $code',
      (tester) async {
        final app = await _App.pump(tester, locale);
        final l10n = app.l10n;
        const page = IntentionCatalogPage;
        final before = _storedGraph(app.raw);
        final changesBefore = _connectionChanges(app.raw);
        final health = l10n.intentionSummaryTags('Здоровье');
        final healthRest = l10n.intentionSummaryTags('Здоровье, Отдых');
        final all = l10n.intentionSummaryTags('Здоровье, Спорт, Отдых');

        // Теги видны и без условий; одноимённые намерения остаются отдельными.
        await _expectResults(tester, page, [
          ('Ходить в парк', healthRest),
          ('Гулять без тегов', l10n.intentionSummaryNoTags),
          ('Читать в тишине', healthRest),
          ('Ходить в зал', all),
          ('Ходить до магазина', health),
          ('Ходить в парк', healthRest),
        ]);
        expect(find.text(l10n.catalogTotalCount(6)), findsOneWidget);
        expect(_conditions(tester, page), isEmpty);

        // Поиск только по обязательным тегам.
        await _addCondition(tester, _health, present: true);
        await _addCondition(tester, _rest, present: true);
        await _expectResults(tester, page, [
          ('Ходить в парк', healthRest),
          ('Читать в тишине', healthRest),
          ('Ходить в зал', all),
          ('Ходить в парк', healthRest),
        ]);
        await _addCondition(tester, _sport, present: false);
        final combined = [
          'Здоровье',
          'Отдых',
          l10n.intentionTagConditionAbsent('Спорт'),
        ];
        expect(_conditions(tester, page), combined);
        await _expectResults(tester, page, [
          ('Ходить в парк', healthRest),
          ('Читать в тишине', healthRest),
          ('Ходить в парк', healthRest),
        ]);

        // Название, обязательные и исключённые теги действуют одновременно.
        await tester.enterText(
          find.byKey(const ValueKey('catalog-filter-field')),
          'ходить',
        );
        await _expectResults(tester, page, [
          ('Ходить в парк', healthRest),
          ('Ходить в парк', healthRest),
        ]);
        expect(find.text(l10n.catalogTotalCount(2)), findsOneWidget);

        // Смена охвата сохраняет совместный фильтр.
        await _selectScope(tester, l10n.catalogScopeArchived);
        await _expectResults(tester, page, [('Ходить в парк', healthRest)]);
        expect(find.text(l10n.catalogTotalCount(1)), findsOneWidget);
        expect(_conditions(tester, page), combined);
        await _selectScope(tester, l10n.catalogScopeActive);
        await _expectResults(tester, page, [
          ('Ходить в парк', healthRest),
          ('Ходить в парк', healthRest),
        ]);

        // Уже выбранный тег отмечен; закрытие без выбора сохраняет условия.
        await _tap(
          tester,
          find.byKey(const ValueKey('intention-tag-conditions-add')),
        );
        final sportRow = find.byKey(
          ValueKey('tag-condition-picker-row-${tagFixtureId(_sport)}'),
        );
        await _until(tester, sportRow);
        expect(
          find.descendant(
            of: sportRow,
            matching: find.text(l10n.tagConditionPickerSelectedAbsent),
          ),
          findsOneWidget,
        );
        await _closeTop(tester, TagConditionPickerPage);
        expect(_conditions(tester, page), combined);

        // Повторный выбор тега меняет надобность, а не добавляет условие.
        await _addCondition(tester, _sport, present: true);
        expect(_conditions(tester, page), ['Здоровье', 'Отдых', 'Спорт']);
        await _expectResults(tester, page, [('Ходить в зал', all)]);
        await _tap(
          tester,
          find.byKey(
            ValueKey('intention-tag-condition-toggle-${tagFixtureId(_sport)}'),
          ),
        );
        expect(_conditions(tester, page), combined);
        await _expectResults(tester, page, [
          ('Ходить в парк', healthRest),
          ('Ходить в парк', healthRest),
        ]);

        // Поиск только с исключением допускает намерение без тегов.
        await tester.enterText(
          find.byKey(const ValueKey('catalog-filter-field')),
          '',
        );
        await _removeCondition(tester, _health);
        await _removeCondition(tester, _rest);
        expect(_conditions(tester, page), [
          l10n.intentionTagConditionAbsent('Спорт'),
        ]);
        await _expectResults(tester, page, [
          ('Ходить в парк', healthRest),
          ('Гулять без тегов', l10n.intentionSummaryNoTags),
          ('Читать в тишине', healthRest),
          ('Ходить до магазина', health),
          ('Ходить в парк', healthRest),
        ]);

        // Пустая выдача по условиям отличается от пустого охвата.
        await _tap(
          tester,
          find.byKey(
            ValueKey('intention-tag-condition-toggle-${tagFixtureId(_sport)}'),
          ),
        );
        await _addCondition(tester, _health, present: false);
        await _until(tester, find.text(l10n.catalogTagConditionsEmpty));
        expect(find.text(l10n.catalogActiveEmpty), findsNothing);
        expect(_results(tester, page), isEmpty);

        // Поиск не выполняет команд тегов и не меняет граф.
        expect(_storedGraph(app.raw), before);
        expect(_connectionChanges(app.raw), changesBefore);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

final class _App {
  _App(this.raw, this.container, this.router, this.fault, this.l10n);

  final sqlite.Database raw;
  final ProviderContainer container;
  final AppRouter router;
  final _RefreshFault fault;
  final AppLocalizations l10n;

  static Future<_App> pump(WidgetTester tester, Locale locale) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    tester.binding.platformDispatcher.localesTestValue = [locale];
    addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    late sqlite.Database raw;
    final fault = _RefreshFault();
    final runtime = AppRuntime(
      quickCreationModeStore: InMemoryQuickCreationModeStore(),
      connectionFactory: () => observeConfiguredLocalDatabaseConnection(
        openInMemoryLocalDatabase(setup: (database) => raw = database),
        fault,
      ),
      diagnosticsSink: fault,
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await runtime.shutdown();
    });
    final ready = (await tester.runAsync(runtime.bootstrap)) as AppRuntimeReady;
    _seed(raw);
    await tester.pumpWidget(MainApp(runtime: runtime));
    await openIntentionGraph(tester, waitFor: _until);
    await _until(tester, find.byKey(const ValueKey('catalog-open-tags')));
    await _until(tester, find.byType(IntentionSummaryView));
    await tester.pumpAndSettle();
    return _App(
      raw,
      ready.container,
      ready.container.read(appRouterProvider),
      fault,
      lookupAppLocalizations(locale),
    );
  }
}

/// Управляемый отказ SQLite только для чтения согласования выдачи.
///
/// Диагностика репозитория отмечает границы этого чтения, поэтому команды
/// тегов и обычные порции каталога выполняются без отказа.
final class _RefreshFault extends LocalDatabaseConnectionObserver
    implements DiagnosticsSink {
  Object? failure;
  var failedReads = 0;
  var _reconciling = false;

  @override
  void record(DiagnosticsEvent event) {
    if (event is CatalogReconciliationReadDiagnosticsEvent) {
      _reconciling = event.status is DiagnosticsStarted;
    }
  }

  @override
  void beforeStatement(LocalDatabaseSqlStatement statement) {
    final failure = this.failure;
    if (failure == null ||
        !_reconciling ||
        statement.operation != LocalDatabaseSqlOperation.select ||
        !statement.statements.any((sql) => sql.contains('json_each('))) {
      return;
    }
    failedReads += 1;
    throw failure;
  }
}

/// Намерения с тегами «Здоровье», «Спорт» и «Отдых», связи первого
/// намерения и его дневной выбор с путём по одной из активных связей.
void _seed(sqlite.Database database) {
  for (final (number, name) in [
    (_health, 'Здоровье'),
    (_sport, 'Спорт'),
    (_rest, 'Отдых'),
  ]) {
    database.execute('INSERT INTO tags (id, name) VALUES (?, ?)', [
      tagFixtureId(number),
      name,
    ]);
  }
  for (final (number, title, ready, archived, tags) in [
    (1, 'Ходить в парк', 1, 0, [_health, _rest]),
    (2, 'Ходить до магазина', 1, 0, [_health]),
    (3, 'Ходить в зал', 1, 0, [_health, _sport, _rest]),
    (4, 'Читать в тишине', 0, 0, [_health, _rest]),
    (5, 'Ходить в парк', 1, 1, [_health, _rest]),
    (6, 'Гулять без тегов', 0, 0, <int>[]),
    (7, 'Ходить в парк', 0, 0, [_health, _rest]),
  ]) {
    database.execute(
      'INSERT INTO intentions (id, title, is_action_ready, is_archived, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)',
      [tagFixtureId(number), title, ready, archived, number, number],
    );
    for (final tag in tags) {
      database.execute(
        'INSERT INTO tag_assignments (tag_id, intention_id) VALUES (?, ?)',
        [tagFixtureId(tag), tagFixtureId(number)],
      );
    }
  }
  for (final (number, related, archived) in [
    (_pathRelation, 2, 0),
    (_archivedRelation, 5, 1),
    (_activeRelation, 4, 0),
  ]) {
    database.execute(
      'INSERT INTO long_term_relations (id, source_intention_id, related_intention_id, type, priority, is_archived) VALUES (?, ?, ?, ?, ?, ?)',
      [
        tagFixtureId(number),
        tagFixtureId(1),
        tagFixtureId(related),
        'need',
        2,
        archived,
      ],
    );
  }
  database.execute(
    'INSERT INTO daily_choices (id, source_intention_id, selected_intention_id, choice_date, is_completed) VALUES (?, ?, ?, ?, ?)',
    [
      tagFixtureId(_dailyChoice),
      tagFixtureId(1),
      tagFixtureId(2),
      '2026-09-25',
      0,
    ],
  );
  database.execute(
    'INSERT INTO daily_choice_path_steps (id, daily_choice_id, long_term_relation_id) VALUES (?, ?, ?)',
    [
      tagFixtureId(202),
      tagFixtureId(_dailyChoice),
      tagFixtureId(_pathRelation),
    ],
  );
}

Map<String, List<List<Object?>>> _storedGraph(sqlite.Database raw) => {
  ...retainedTagFixtureGraph(raw),
  for (final table in ['tags', 'tag_assignments'])
    table: raw
        .select('SELECT * FROM $table ORDER BY rowid')
        .map((row) => row.values.toList())
        .toList(),
};

Object? _connectionChanges(sqlite.Database raw) =>
    raw.select('SELECT total_changes() AS count').single['count'];

/// Видимые результаты поиска страницы в порядке выдачи.
List<_Row> _results(WidgetTester tester, Type page) => [
  for (final view
      in find
          .descendant(
            of: find.byType(page),
            matching: find.byType(IntentionSummaryView),
          )
          .evaluate())
    switch (find
        .descendant(
          of: find.byElementPredicate((element) => element == view),
          matching: find.byType(Text),
        )
        .evaluate()
        .map((element) => (element.widget as Text).data!)
        .toList()) {
      [final title, final tags, ...] => (title, tags),
      final texts => fail('Строка результата без названия и тегов: $texts'),
    },
];

/// Подписи чипов выбранных условий страницы в порядке добавления.
List<String> _conditions(WidgetTester tester, Type page) => [
  for (final label
      in find
          .descendant(
            of: find.byType(page),
            matching: find.byKey(
              const ValueKey('intention-tag-condition-label'),
            ),
          )
          .evaluate())
    (label.widget as Text).data!,
];

Future<void> _expectResults(
  WidgetTester tester,
  Type page,
  List<_Row> expected,
) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    final actual = _results(tester, page);
    if (actual.length == expected.length &&
        [
          for (var index = 0; index < actual.length; index++)
            actual[index] == expected[index],
        ].every((same) => same)) {
      break;
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  await tester.pumpAndSettle();
  expect(_results(tester, page), expected);
}

/// Добавляет условие через экран поиска тега действием «Есть» или «Нет».
Future<void> _addCondition(
  WidgetTester tester,
  int tag, {
  required bool present,
}) async {
  await _tap(
    tester,
    find.byKey(const ValueKey('intention-tag-conditions-add')),
  );
  final requirement = present ? 'mustBePresent' : 'mustBeAbsent';
  await _tap(
    tester,
    find.byKey(
      ValueKey('tag-condition-picker-$requirement-${tagFixtureId(tag)}'),
    ),
  );
  await _waitFor(
    tester,
    () => find.byType(TagConditionPickerPage).evaluate().isEmpty,
  );
  await tester.pumpAndSettle();
}

Future<void> _removeCondition(WidgetTester tester, int tag) async {
  await _tap(
    tester,
    find.byKey(ValueKey('intention-tag-condition-remove-${tagFixtureId(tag)}')),
  );
  await tester.pumpAndSettle();
}

Future<void> _selectScope(WidgetTester tester, String label) async {
  await _tap(tester, find.byKey(const ValueKey('catalog-scope-control')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

/// Закрывает верхнюю страницу системным действием «назад».
Future<void> _closeTop(WidgetTester tester, Type page) async {
  await tester.binding.handlePopRoute();
  await _waitFor(tester, () => find.byType(page).evaluate().isEmpty);
  await tester.pumpAndSettle();
}

Future<void> _until(WidgetTester tester, Finder finder) =>
    _waitFor(tester, () => finder.evaluate().isNotEmpty);

Future<void> _waitFor(WidgetTester tester, bool Function() done) async {
  for (var attempt = 0; attempt < 100 && !done(); attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(done(), isTrue);
}

/// Нажимает элемент [finder], прокручивая к нему, только если он не
/// принимает нажатие: прокрутка к видимой строке выдачи увела бы параметры
/// поиска каталога намерений за верхний край страницы.
Future<void> _tap(WidgetTester tester, Finder finder) async {
  await _until(tester, finder);
  await tester.pumpAndSettle();
  if (finder.hitTestable().evaluate().isEmpty) {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
  }
  await tester.tap(finder);
  await tester.pump();
}
