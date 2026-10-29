import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/l10n/app_localizations_ru.dart';
import 'package:doable/src/long_term_relation/application/relation_group_page.dart';
import 'package:doable/src/long_term_relation/presentation/relation_list_status.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'neighborhood/neighborhood_test_support.dart';

void main() {
  final l10n = AppLocalizationsRu();
  final failures = <(String, RelationGroupReadFailure, String, String)>[
    (
      'недоступность',
      const RelationGroupUnavailableFailure(),
      l10n.relationNeighborhoodInitialUnavailable,
      l10n.relationNeighborhoodLoadMoreUnavailable,
    ),
    (
      'повреждение',
      const RelationGroupCorruptionFailure(),
      l10n.relationNeighborhoodInitialCorruption,
      l10n.relationNeighborhoodLoadMoreCorruption,
    ),
    (
      'непредвиденный отказ',
      const RelationGroupUnexpectedFailure(),
      l10n.relationNeighborhoodInitialUnexpected,
      l10n.relationNeighborhoodLoadMoreUnexpected,
    ),
    (
      'устаревший снимок',
      const RelationGroupSnapshotExpired(),
      l10n.relationNeighborhoodInitialInvalid,
      l10n.relationNeighborhoodLoadMoreInvalid,
    ),
    (
      'отсутствие намерения',
      RelationGroupIntentionNotFoundFailure(testIntentionId(1)),
      l10n.relationNeighborhoodIntentionNotFound,
      l10n.relationNeighborhoodLoadMoreInvalid,
    ),
  ];

  for (final (name, failure, initialMessage, loadMoreMessage) in failures) {
    final retryable = failure is RelationGroupUnavailableFailure;
    testWidgets(
      'отказ «$name» называет категорию, а повтор есть только при недоступности',
      (tester) async {
        var retries = 0;
        Future<void> retry() async => retries++;
        final statuses =
            <(String, RelationListStatus Function(AppLocalizations))>[
              (
                initialMessage,
                (l10n) => RelationListStatus.initialFailure(
                  l10n,
                  failure: failure,
                  onRetry: retry,
                ),
              ),
              (
                loadMoreMessage,
                (l10n) => RelationListStatus.loadMoreFailure(
                  l10n,
                  failure: failure,
                  onRetry: retry,
                ),
              ),
              (
                l10n.relationNeighborhoodRefreshFailed,
                (l10n) => RelationListStatus.refreshFailure(
                  l10n,
                  failure: failure,
                  onRetry: retry,
                ),
              ),
            ];

        for (final (message, build) in statuses) {
          await _pump(tester, build);

          expect(find.text(message), findsOneWidget);
          expect(
            find.widgetWithText(FilledButton, l10n.commonRetry),
            retryable ? findsOneWidget : findsNothing,
          );
          if (retryable) {
            await tester.tap(
              find.widgetWithText(FilledButton, l10n.commonRetry),
            );
          }
        }
        expect(retries, retryable ? statuses.length : 0);
      },
    );
  }

  testWidgets('повтор не показывается, когда вкладка не передала обработчик', (
    tester,
  ) async {
    await _pump(
      tester,
      (l10n) => RelationListStatus.loadMoreFailure(
        l10n,
        failure: const RelationGroupUnavailableFailure(),
        onRetry: null,
      ),
    );

    expect(
      find.text(l10n.relationNeighborhoodLoadMoreUnavailable),
      findsOneWidget,
    );
    expect(find.byType(FilledButton), findsNothing);
  });

  testWidgets(
    'первое чтение, подгрузка и обновление показывают индикатор в живой области',
    (tester) async {
      final statuses =
          <(String, RelationListStatus Function(AppLocalizations))>[
            (
              l10n.relationNeighborhoodSummaryLoading,
              (l10n) => RelationListStatus.initialLoad(l10n),
            ),
            (
              l10n.relationNeighborhoodLoadingMore,
              (l10n) => RelationListStatus.loadingMore(l10n),
            ),
            (
              l10n.relationNeighborhoodRefreshing,
              (l10n) => RelationListStatus.refreshing(l10n),
            ),
          ];

      for (final (message, build) in statuses) {
        await _pump(tester, build);

        expect(find.text(message), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(_isLiveRegion(tester), isTrue);
      }
    },
  );

  testWidgets('отсутствие намерения и конец списка без индикатора и повтора', (
    tester,
  ) async {
    final statuses = <(String, RelationListStatus Function(AppLocalizations))>[
      (
        l10n.relationNeighborhoodIntentionNotFound,
        (l10n) => RelationListStatus.intentionNotFound(l10n),
      ),
      (
        l10n.relationNeighborhoodConfirmedEnd,
        (l10n) => RelationListStatus.confirmedEnd(l10n),
      ),
    ];

    for (final (message, build) in statuses) {
      await _pump(tester, build);

      expect(find.text(message), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(FilledButton), findsNothing);
      expect(_isLiveRegion(tester), isFalse);
    }
  });
}

bool _isLiveRegion(WidgetTester tester) => tester
    .widget<Semantics>(
      find
          .descendant(
            of: find.byType(RelationListStatus),
            matching: find.byType(Semantics),
          )
          .first,
    )
    .properties
    .liveRegion!;

Future<void> _pump(
  WidgetTester tester,
  RelationListStatus Function(AppLocalizations l10n) build,
) => tester.pumpWidget(
  MaterialApp(
    locale: const Locale('ru'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: Builder(builder: (context) => build(AppLocalizations.of(context))),
    ),
  ),
);
