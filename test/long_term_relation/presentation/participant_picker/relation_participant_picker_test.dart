import 'dart:async';

import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/app/routing/app_router.dart';
import 'package:doable/src/app/routing/app_router.gr.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/intention/application/intention_catalog.dart'
    hide IntentionCatalogPage;
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/intention/presentation/catalog/catalog_paging_policy.dart';
import 'package:doable/src/intention/presentation/details/intention_details_page.dart';
import 'package:doable/src/intention/presentation/intention_summary_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../intention/presentation/catalog/catalog_test_support.dart'
    show testSummary;
import 'participant_picker_test_support.dart';

void main() {
  testWidgets('запрашивает активные намерения ограниченной порцией', (
    tester,
  ) async {
    final repository = ControlledParticipantPickerRepository();
    addTearDown(repository.dispose);
    final router = await _pumpAppWithCatalog(tester, repository);
    addTearDown(router.dispose);

    unawaited(_pushPicker(router, excludedIndex: 9));
    await _settleRoute(tester);

    final query = repository.queryAt(1);
    expect(query.scope, IntentionScope.active);
    expect(query.pageSize, 100);
    expect(query.titleFilter, isNull);
    expect(query.cursor, isNull);
  });

  testWidgets('применяет буквальный фильтр названия к тому же каталогу', (
    tester,
  ) async {
    final repository = ControlledParticipantPickerRepository();
    addTearDown(repository.dispose);
    final router = await _pumpAppWithCatalog(tester, repository);
    addTearDown(router.dispose);

    unawaited(_pushPicker(router, excludedIndex: 9));
    await _settleRoute(tester);
    _completePage(repository, 1, [testSummary(index: 1, title: 'Ходить')]);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('participant-picker-filter-field')),
      '100%',
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    expect(repository.queries, hasLength(3));
    expect(repository.queryAt(2).titleFilter?.map((value) => value), '100%');
    expect(repository.queryAt(2).scope, IntentionScope.active);
  });

  testWidgets('исключает второго участника связи по идентификатору', (
    tester,
  ) async {
    final repository = ControlledParticipantPickerRepository();
    addTearDown(repository.dispose);
    final router = await _pumpAppWithCatalog(tester, repository);
    addTearDown(router.dispose);

    unawaited(_pushPicker(router, excludedIndex: 2));
    await _settleRoute(tester);
    _completePage(repository, 1, [
      testSummary(index: 1, title: 'Быть здоровым'),
      testSummary(index: 2, title: 'Много ходить'),
    ]);
    await tester.pumpAndSettle();

    expect(find.text('Быть здоровым'), findsOneWidget);
    expect(find.text('Много ходить'), findsNothing);
  });

  testWidgets(
    'сохраняет одноимённые намерения отдельными строками с их количествами',
    (tester) async {
      final repository = ControlledParticipantPickerRepository();
      addTearDown(repository.dispose);
      final router = await _pumpAppWithCatalog(tester, repository);
      addTearDown(router.dispose);

      unawaited(_pushPicker(router, excludedIndex: 9));
      await _settleRoute(tester);
      _completePage(repository, 1, [
        testSummary(index: 1, title: 'Позвонить', activeRelationCount: 2),
        testSummary(index: 2, title: 'Позвонить', activeRelationCount: 5),
      ]);
      await tester.pumpAndSettle();

      expect(find.text('Позвонить'), findsNWidgets(2));
      expect(find.text('Active relations: 2'), findsOneWidget);
      expect(find.text('Active relations: 5'), findsOneWidget);
    },
  );

  testWidgets('открывает подробные данные намерения без завершения выбора', (
    tester,
  ) async {
    final repository = ControlledParticipantPickerRepository();
    addTearDown(repository.dispose);
    final router = await _pumpAppWithCatalog(tester, repository);
    addTearDown(router.dispose);

    var selectionCompleted = false;
    final selection = _pushPicker(router, excludedIndex: 9)
      ..whenComplete(() => selectionCompleted = true);
    await _settleRoute(tester);
    _completePage(repository, 1, [
      testSummary(index: 1, title: 'Позвонить'),
      testSummary(index: 2, title: 'Позвонить'),
    ]);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Open intention details').first);
    await _settleRoute(tester);

    expect(find.byType(IntentionDetailsPage), findsOneWidget);
    expect(selectionCompleted, isFalse);

    await router.maybePop();
    await _settleRoute(tester);
    await tester.tap(find.text('Позвонить').first);
    await tester.pumpAndSettle();

    expect(await selection, _testIntentionId(1));
  });

  testWidgets('возвращает типизированный идентификатор после явного выбора', (
    tester,
  ) async {
    final repository = ControlledParticipantPickerRepository();
    addTearDown(repository.dispose);
    final router = await _pumpAppWithCatalog(tester, repository);
    addTearDown(router.dispose);

    final selection = _pushPicker(router, excludedIndex: 9);
    await _settleRoute(tester);
    _completePage(repository, 1, [
      testSummary(index: 1, title: 'Быть здоровым'),
      testSummary(index: 2, title: 'Много ходить'),
    ]);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Много ходить'));
    await tester.pumpAndSettle();

    expect(await selection, _testIntentionId(2));
  });

  testWidgets('отмена возвращает пустой результат', (tester) async {
    final repository = ControlledParticipantPickerRepository();
    addTearDown(repository.dispose);
    final router = await _pumpAppWithCatalog(tester, repository);
    addTearDown(router.dispose);

    final selection = _pushPicker(router, excludedIndex: 9);
    await _settleRoute(tester);
    _completePage(repository, 1, [testSummary(index: 1, title: 'Ходить')]);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('participant-picker-cancel')));
    await tester.pumpAndSettle();

    expect(await selection, isNull);
    expect(repository.queries, hasLength(2));
  });

  testWidgets('показывает пустой выбор, когда доступен только участник связи', (
    tester,
  ) async {
    final repository = ControlledParticipantPickerRepository();
    addTearDown(repository.dispose);
    final router = await _pumpAppWithCatalog(tester, repository);
    addTearDown(router.dispose);

    unawaited(_pushPicker(router, excludedIndex: 1));
    await _settleRoute(tester);
    _completePage(repository, 1, [testSummary(index: 1, title: 'Ходить')]);
    await tester.pumpAndSettle();

    expect(
      find.text('No other intentions are available to select.'),
      findsOneWidget,
    );
    expect(find.text('Ходить'), findsNothing);
  });

  testWidgets('подгружает следующую порцию до конца каталога', (tester) async {
    final repository = ControlledParticipantPickerRepository();
    addTearDown(repository.dispose);
    final router = await _pumpAppWithCatalog(
      tester,
      repository,
      pageSize: 2,
      prefetchRemaining: 1,
    );
    addTearDown(router.dispose);

    unawaited(_pushPicker(router, excludedIndex: 9));
    await _settleRoute(tester);
    repository.complete(
      1,
      ResultSuccess(
        IntentionCatalogFirstPage(
          items: [
            testSummary(index: 1, title: 'Первое'),
            testSummary(index: 2, title: 'Второе'),
          ],
          totalCount: 3,
          nextCursor: const TestPickerCursor(),
          revision: const TestPickerRevision(1),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(repository.queries, hasLength(3));
    expect(repository.queryAt(2).cursor, isNotNull);
    expect(repository.queryAt(2).pageSize, 2);

    repository.complete(
      2,
      ResultSuccess(
        IntentionCatalogContinuationPage(
          items: [testSummary(index: 3, title: 'Третье')],
          nextCursor: null,
          revision: const TestPickerRevision(1),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Третье'), findsOneWidget);
  });

  testWidgets('продолжает каталог, когда порция занята участником связи', (
    tester,
  ) async {
    final repository = ControlledParticipantPickerRepository();
    addTearDown(repository.dispose);
    final router = await _pumpAppWithCatalog(
      tester,
      repository,
      pageSize: 1,
      prefetchRemaining: 0,
    );
    addTearDown(router.dispose);

    final selection = _pushPicker(router, excludedIndex: 1);
    await _settleRoute(tester);
    repository.complete(
      1,
      ResultSuccess(
        IntentionCatalogFirstPage(
          items: [testSummary(index: 1, title: 'Второй участник')],
          totalCount: 2,
          nextCursor: const TestPickerCursor(),
          revision: const TestPickerRevision(1),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Loading more intentions…'), findsOneWidget);
    expect(repository.queries, hasLength(3));

    repository.complete(
      2,
      ResultSuccess(
        IntentionCatalogContinuationPage(
          items: [testSummary(index: 2, title: 'Доступное намерение')],
          nextCursor: null,
          revision: const TestPickerRevision(1),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Второй участник'), findsNothing);
    expect(find.text('Доступное намерение'), findsOneWidget);

    await tester.tap(find.text('Доступное намерение'));
    await tester.pumpAndSettle();

    expect(await selection, _testIntentionId(2));
  });

  testWidgets('поздний ответ прежнего фильтра не изменяет список выбора', (
    tester,
  ) async {
    final repository = ControlledParticipantPickerRepository();
    addTearDown(repository.dispose);
    final router = await _pumpAppWithCatalog(tester, repository);
    addTearDown(router.dispose);

    unawaited(_pushPicker(router, excludedIndex: 9));
    await _settleRoute(tester);

    await tester.enterText(
      find.byKey(const ValueKey('participant-picker-filter-field')),
      'Вт',
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    _completePage(repository, 2, [testSummary(index: 2, title: 'Второе')]);
    await tester.pumpAndSettle();
    _completePage(repository, 1, [testSummary(index: 1, title: 'Первое')]);
    await tester.pumpAndSettle();

    expect(find.text('Второе'), findsOneWidget);
    expect(find.text('Первое'), findsNothing);
  });

  testWidgets('предлагает повторить получение после устранимой ошибки', (
    tester,
  ) async {
    final repository = ControlledParticipantPickerRepository();
    addTearDown(repository.dispose);
    final router = await _pumpAppWithCatalog(tester, repository);
    addTearDown(router.dispose);

    unawaited(_pushPicker(router, excludedIndex: 9));
    await _settleRoute(tester);
    repository.complete(1, const ResultFailure(IntentionUnavailableFailure()));
    await tester.pumpAndSettle();

    expect(
      find.text('Intentions couldn’t be loaded. Try again.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Try again'));
    await tester.pump();
    await tester.pump();

    expect(repository.queries, hasLength(3));
  });

  testWidgets('показывает выбор участника на русском языке', (tester) async {
    final repository = ControlledParticipantPickerRepository();
    addTearDown(repository.dispose);
    final router = await _pumpAppWithCatalog(
      tester,
      repository,
      locale: const Locale('ru'),
    );
    addTearDown(router.dispose);

    unawaited(_pushPicker(router, excludedIndex: 1));
    await _settleRoute(tester);
    _completePage(repository, 1, [testSummary(index: 1, title: 'Ходить')]);
    await tester.pumpAndSettle();

    expect(find.text('Выбор участника'), findsOneWidget);
    expect(find.text('Других намерений для выбора нет.'), findsOneWidget);
  });

  testWidgets('сохраняет выбор доступным при увеличенном тексте', (
    tester,
  ) async {
    final repository = ControlledParticipantPickerRepository();
    addTearDown(repository.dispose);
    final router = await _pumpAppWithCatalog(
      tester,
      repository,
      textScaler: const TextScaler.linear(2),
    );
    addTearDown(router.dispose);

    final selection = _pushPicker(router, excludedIndex: 9);
    await _settleRoute(tester);
    _completePage(repository, 1, [testSummary(index: 1, title: 'Ходить')]);
    await tester.pumpAndSettle();

    expect(find.text('Ходить'), findsOneWidget);
    await tester.tap(find.text('Ходить'));
    await tester.pumpAndSettle();

    expect(await selection, _testIntentionId(1));
  });

  testWidgets('сообщает экранному диктору назначение выбора и перехода', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final repository = ControlledParticipantPickerRepository();
    addTearDown(repository.dispose);
    final router = await _pumpAppWithCatalog(tester, repository);
    addTearDown(router.dispose);

    unawaited(_pushPicker(router, excludedIndex: 9));
    await _settleRoute(tester);
    _completePage(repository, 1, [testSummary(index: 1, title: 'Ходить')]);
    await tester.pumpAndSettle();

    final option = tester.getSemantics(find.byType(IntentionSummaryView));
    expect(option.label, contains('Ходить'));
    expect(option.label, contains('Active relations: 0'));
    expect(option.hint, 'Selects this intention as a relation participant');
    final details = tester.getSemantics(
      find.byTooltip('Open intention details'),
    );
    expect(details.tooltip, 'Open intention details');
    expect(details.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    handle.dispose();
  });

  testWidgets('фильтр выбора не изменяет открытый каталог намерений', (
    tester,
  ) async {
    final repository = ControlledParticipantPickerRepository();
    addTearDown(repository.dispose);
    final router = await _pumpAppWithCatalog(tester, repository);
    addTearDown(router.dispose);

    final selection = _pushPicker(router, excludedIndex: 9);
    await _settleRoute(tester);
    _completePage(repository, 1, [testSummary(index: 1, title: 'Ходить')]);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('participant-picker-filter-field')),
      'Хо',
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    _completePage(repository, 2, [testSummary(index: 1, title: 'Ходить')]);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('participant-picker-cancel')));
    await tester.pumpAndSettle();
    await selection;

    expect(repository.queries, hasLength(3));
    expect(find.text('Total intentions: 1'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('catalog-filter-field')))
          .controller
          ?.text,
      isEmpty,
    );
  });
}

/// Завершает переход к выбору участника, не ожидая подтверждённой порции.
///
/// Ожидание первой порции показывает бесконечный индикатор, поэтому кадры
/// перехода продвигаются явно.
Future<void> _settleRoute(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

IntentionId _testIntentionId(int index) => testSummary(index: index).id;

Future<IntentionId?> _pushPicker(
  AppRouter router, {
  required int excludedIndex,
}) => router.push<IntentionId>(
  RelationParticipantPickerRoute(
    excludedIntentionId: _testIntentionId(excludedIndex),
  ),
);

void _completePage(
  ControlledParticipantPickerRepository repository,
  int index,
  List<IntentionSummary> items,
) => repository.complete(
  index,
  ResultSuccess(
    IntentionCatalogFirstPage(
      items: items,
      totalCount: items.length,
      nextCursor: null,
      revision: const TestPickerRevision(1),
    ),
  ),
);

Future<AppRouter> _pumpAppWithCatalog(
  WidgetTester tester,
  ControlledParticipantPickerRepository repository, {
  Locale locale = const Locale('en'),
  int pageSize = 100,
  int prefetchRemaining = 30,
  TextScaler textScaler = TextScaler.noScaling,
}) async {
  final router = AppRouter();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        personalGraphRepositoryProvider.overrideWithValue(repository),
        catalogPagingPolicyProvider.overrideWithValue(
          CatalogPagingPolicy(
            pageSize: pageSize,
            prefetchRemaining: prefetchRemaining,
            filterDebounce: const Duration(milliseconds: 250),
          ),
        ),
      ],
      retry: (retryCount, error) => null,
      child: MaterialApp.router(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router.config(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: textScaler),
          child: child!,
        ),
      ),
    ),
  );
  await tester.pump();
  _completePage(repository, 0, [testSummary(index: 1, title: 'Ходить')]);
  await tester.pumpAndSettle();
  return router;
}
