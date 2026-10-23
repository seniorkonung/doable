part of 'app_shell_layout_test.dart';

void _registerOrdinaryLayoutTests() {
  _registerOrdinaryPaginationTests();
  // Раскладку определяют вставки окна. Язык и ширина экрана ветвлений не
  // добавляют, поэтому берём русский — самые длинные подписи — и экран телефона,
  // для которого спецификация требует доступности над панелью.
  const locale = Locale('ru');
  const screen = _screen;
  for (final insets in [_safeArea, _keyboardOpen]) {
    final conditions = '${locale.languageCode}, ${insets.name}';
    testWidgets('правка намерения при тексте 2×, $conditions: поля и '
        'действия доступны над клавиатурой и панелью', (tester) async {
      final app = await _start(
        tester,
        locale: locale,
        screen: screen,
        insets: insets,
      );
      final l10n = lookupAppLocalizations(locale);
      unawaited(
        app.router.push(
          IntentionDetailsRoute(intentionId: _layoutIntentionId(1)),
        ),
      );
      await _until(
        tester,
        find.byKey(const ValueKey('intention-details-title')),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text(l10n.detailsEditAction), 200);
      await tester.pumpAndSettle();
      expect(find.text(l10n.detailsEditAction).hitTestable(), findsOneWidget);
      await tester.tap(find.text(l10n.detailsEditAction));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      for (final field in ['title', 'description']) {
        final input = find.byKey(ValueKey('intention-details-edit-$field'));
        await tester.enterText(input, 'Изменённое $field');
        await tester.ensureVisible(input);
        await tester.pumpAndSettle();
        _expectFullyVisible(tester, input, insets);
        expect(input.hitTestable(), findsOneWidget);
      }
      for (final action in ['cancel', 'submit']) {
        final button = find.byKey(ValueKey('intention-details-edit-$action'));
        await tester.ensureVisible(button);
        await tester.pumpAndSettle();
        _expectFullyVisible(tester, button, insets);
        expect(button.hitTestable(), findsOneWidget);
      }
      await tester.tap(
        find.byKey(const ValueKey('intention-details-edit-submit')),
      );
      await _until(tester, find.text('Изменённое title'));
      await _waitFor(tester, () => find.byType(TextField).evaluate().isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('быстрое создание из каталогов при тексте 2×, $conditions: '
        'кнопка помещается в панели и запускает оба режима', (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        final app = await _start(
          tester,
          locale: locale,
          screen: screen,
          insets: insets,
        );
        await _select(tester, AppDestination.intentionGraph);
        _expectQuickCreationInPanel(tester, insets);
        await openQuickCreation(
          tester,
          QuickCreationMode.intention,
          openedPage: find.byType(IntentionEditorPage),
          wait: _until,
        );
        expect(find.byType(IntentionEditorPage), findsOneWidget);
        await app.router.maybePop();
        await tester.pumpAndSettle();
        await _select(tester, AppDestination.dailyChoices);
        _expectQuickCreationInPanel(tester, insets);
        await openDailyChoiceQuickCreation(
          tester,
          ChoicePathDraftDirection.bottomUp,
          openedPage: find.byType(DailyChoiceActionPickerPage),
          wait: _until,
        );
        expect(find.byType(DailyChoiceActionPickerPage), findsOneWidget);
        await app.router.maybePop();
        await tester.pumpAndSettle();
        _expectQuickCreationInPanel(tester, insets);
        final l10n = lookupAppLocalizations(locale);
        final name =
            '${l10n.quickCreationLabel}, '
            '${l10n.quickCreationModeDailyChoice}';
        expect(
          find.semantics.byPredicate((node) => node.label == name),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    });

    testWidgets('подробные просмотры, $conditions: последние действия '
        'доступны над панелью без двойного нижнего отступа', (tester) async {
      final app = await _start(
        tester,
        locale: locale,
        screen: screen,
        insets: insets,
      );
      final relationId = (LongTermRelationId.decode(
        tagFixtureId(_relation),
      ) as LongTermRelationIdDecodingSuccess).id;
      unawaited(app.router.push(RelationDetailsRoute(relationId: relationId)));
      await _until(
        tester,
        find.byKey(const ValueKey('relation-details-phrase')),
      );
      await tester.pumpAndSettle();
      await _scrollToEnd(tester, find.byType(RelationDetailsPage));
      final participant = find.byKey(
        const ValueKey('relation-details-related-participant'),
      );
      _expectFullyVisible(tester, participant, insets);
      expect(participant.hitTestable(), findsOneWidget);
      await tester.tap(participant);
      await tester.pumpAndSettle();
      expect(app.router.current.name, IntentionDetailsRoute.name);
      app.router.pop();
      await tester.pumpAndSettle();

      unawaited(
        app.router.push(
          DailyChoiceDetailsRoute(choiceId: _dailyChoiceId(_firstChoice)),
        ),
      );
      await _until(
        tester,
        find.byKey(const ValueKey('daily-choice-delete-open')),
      );
      await tester.pumpAndSettle();
      await _scrollToEnd(tester, find.byType(DailyChoiceDetailsPage));
      final last = find.byKey(const ValueKey('daily-choice-intention-2'));
      _expectFullyVisible(tester, last, insets);
      expect(last.hitTestable(), findsOneWidget);
      final delete = find.byKey(const ValueKey('daily-choice-delete-open'));
      _expectFullyVisible(tester, delete, insets);
      expect(delete.hitTestable(), findsOneWidget);
      final page = find.byType(DailyChoiceDetailsPage);
      final body = find
          .descendant(of: page, matching: find.byType(SafeArea))
          .first;
      final expectedBottom =
          screen.height - math.max(insets.keyboard, insets.barExtent);
      expect(tester.getRect(body).bottom, expectedBottom);
      await tester.tap(delete);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('дневной выбор, $conditions: общее сообщение видно над '
        'панелью до и после перехода', (tester) async {
      final app = await _start(
        tester,
        locale: locale,
        screen: screen,
        insets: insets,
      );
      _acceptArchive(app, intention: 2);
      await _until(tester, _messageOf(2));
      await tester.pumpAndSettle();
      unawaited(
        app.router.push(
          DailyChoiceDetailsRoute(choiceId: _dailyChoiceId(_firstChoice)),
        ),
      );
      await _until(tester, find.byType(DailyChoiceDetailsPage));
      await tester.pumpAndSettle();
      _expectLayoutMessage(tester, insets);
      await _closeMessage(tester);
      _acceptArchive(app, intention: 3);
      await _until(tester, _messageOf(3));
      await tester.pumpAndSettle();
      _expectLayoutMessage(tester, insets);
      expect(_messageOf(2), findsNothing);
      await _closeMessage(tester);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(_messages, findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}

/// Кнопка занимает место в панели, а не в области содержимого над ней.
void _expectQuickCreationInPanel(WidgetTester tester, _Insets insets) {
  final button = quickCreationAction();
  expect(button.hitTestable(), findsOneWidget);
  final rect = tester.getRect(button);
  final panel = tester.getRect(find.byType(AppNavigationBar));
  final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
  expect(rect.left, greaterThanOrEqualTo(panel.left));
  expect(rect.right, lessThanOrEqualTo(panel.right));
  expect(rect.top, greaterThanOrEqualTo(panel.top));
  expect(rect.bottom, lessThanOrEqualTo(panel.bottom - insets.padding));
  expect(rect.left, greaterThanOrEqualTo(0));
  expect(rect.right, lessThanOrEqualTo(screen.width));
  expect(rect.top, greaterThanOrEqualTo(insets.safeTop));
  expect(rect.bottom, lessThanOrEqualTo(screen.height - insets.padding));
}

void _expectLayoutMessage(WidgetTester tester, _Insets insets) {
  expect(_messages, findsOneWidget);
  final bar = tester.getRect(find.byType(AppNavigationBar));
  final message = tester.getRect(find.byType(SnackBar));
  final height = tester.view.physicalSize.height / tester.view.devicePixelRatio;
  expect(message.bottom, height - math.max(insets.keyboard, insets.barExtent));
  expect(message.bottom, lessThanOrEqualTo(bar.top));
  expect(_messages.hitTestable(), findsOneWidget);
  expect(tester.takeException(), isNull);
}

void _registerOrdinaryPaginationTests() {
  // Раскладку определяют вставки окна. Язык и ширина экрана ветвлений не
  // добавляют, поэтому берём русский — самые длинные подписи — и экран телефона,
  // для которого спецификация требует доступности над панелью.
  const locale = Locale('ru');
  const screen = _screen;
  for (final insets in [_safeArea, _keyboardOpen]) {
    final conditions = '${locale.languageCode}, ${insets.name}';
    testWidgets('группа связей, $conditions: отказ продолжения, повтор '
        'и последняя строка доступны над панелью', (tester) async {
      final faults = _ReadFaults();
      final app = await _start(
        tester,
        locale: locale,
        screen: screen,
        insets: insets,
        intentions: _lastLayoutRelation,
        observer: faults,
        seedAdditional: _seedOrdinaryLayout,
      );
      final l10n = lookupAppLocalizations(locale);
      unawaited(
        app.router.push(
          IntentionDetailsRoute(intentionId: _layoutIntentionId(1)),
        ),
      );
      await _until(
        tester,
        find.byKey(const ValueKey('intention-details-title')),
      );
      await _settle(tester);
      faults.isFailing = true;
      await _scrollToEnd(tester, find.byType(IntentionDetailsPage));
      final failure = find.text(l10n.relationNeighborhoodLoadMoreUnavailable);
      _expectFullyVisible(tester, failure, insets);
      final retry = find.widgetWithText(FilledButton, l10n.commonRetry);
      _expectFullyVisible(tester, retry, insets);
      expect(retry.hitTestable(), findsOneWidget);
      faults.isFailing = false;
      faults.pause();
      await tester.tap(retry);
      await tester.pump();
      final loading = find.text(l10n.relationNeighborhoodLoadingMore);
      expect(loading, findsOneWidget);
      await _expectLoadingFooter(tester, loading, insets);
      faults.resume();
      await _settle(tester);
      await _scrollToEnd(tester, find.byType(IntentionDetailsPage));
      final end = find.text(l10n.relationNeighborhoodConfirmedEnd);
      _expectFullyVisible(tester, end, insets);
      final row = find.byKey(
        ValueKey(
          'relation-neighborhood-row-${tagFixtureId(5000 + _lastLayoutRelation)}',
        ),
      );
      final last = find
          .descendant(of: row, matching: find.byType(InkWell))
          .first;
      await tester.ensureVisible(last);
      await tester.pumpAndSettle();
      _expectFullyVisible(tester, last, insets);
      expect(last.hitTestable(), findsOneWidget);
      await tester.tap(last);
      await tester.pumpAndSettle();
      expect(find.byType(RelationDetailsPage), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}

/// Во время задержанного чтения прокрутка не ждёт остановки индикатора.
Future<void> _expectLoadingFooter(
  WidgetTester tester,
  Finder message,
  _Insets insets,
) async {
  final scrollable = tester.state<ScrollableState>(
    find.byType(Scrollable).last,
  );
  scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
  await tester.pump();
  _expectFullyVisible(tester, message, insets);
  _expectFullyVisible(tester, find.byType(CircularProgressIndicator), insets);
  expect(tester.takeException(), isNull);
}

const _lastLayoutRelation = 53;

/// Две порции связей одной исходящей группы.
void _seedOrdinaryLayout(sqlite.Database database) {
  seedRawGraph(database, () {
    // Вместе со связью из основного засева у первого намерения 52 связи.
    for (var number = 3; number <= _lastLayoutRelation; number++) {
      database.execute(
        'INSERT INTO long_term_relations (id, source_intention_id, related_intention_id, type, priority, is_archived) VALUES (?, ?, ?, ?, ?, ?)',
        [
          tagFixtureId(5000 + number),
          tagFixtureId(1),
          tagFixtureId(number),
          'need',
          2,
          0,
        ],
      );
    }
  });
}

IntentionId _layoutIntentionId(int number) =>
    (IntentionId.decode(tagFixtureId(number)) as IntentionIdDecodingSuccess).id;
