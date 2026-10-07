part of 'creation_flows_integration_test.dart';

void _registerAccessibilityTests() {
  const devices = [
    (name: 'телефон вертикально', size: Size(400, 800)),
    (name: 'планшет вертикально', size: Size(800, 1280)),
    (name: 'планшет горизонтально', size: Size(1280, 800)),
  ];
  for (final flow in _Flow.values) {
    for (final locale in [const Locale('ru'), const Locale('en')]) {
      for (final device in devices) {
        testWidgets(
          '${flow.label}: действия и сообщения на ${locale.languageCode}, '
          '${device.name}, клавиатура и текст 2.6',
          (tester) async {
            final semantics = tester.ensureSemantics();
            try {
              final app = await _start(tester, locale: locale);
              const origin = IntentionCreationOrigin.deep;
              final history = await origin.open(
                tester,
                app.router,
                participantId: durabilityIntention(2),
                waitFor: (tester, finder) =>
                    _until(tester, () => finder.evaluate().isNotEmpty),
              );
              await flow.open(tester, app, origin);
              await flow.fill(tester);
              tester.view.physicalSize = device.size;
              tester.view.viewInsets = const FakeViewPadding(bottom: 260);
              tester.platformDispatcher.textScaleFactorTestValue = 2.6;
              addTearDown(
                tester.platformDispatcher.clearTextScaleFactorTestValue,
              );
              await tester.pumpAndSettle();
              if (flow == _Flow.intention) {
                _expectAction(
                  tester,
                  _key('intention-editor-close'),
                  app.l10n.editorCloseFormAction,
                );
                final save = _key(flow.submit);
                expect(save.hitTestable(), findsOneWidget);
              } else {
                final cancel = find.widgetWithText(
                  TextButton,
                  app.l10n.creationCancelAction,
                );
                await _reveal(tester, cancel);
                await tester.pumpAndSettle();
                _expectAction(
                  tester,
                  find.bySemanticsLabel(app.l10n.creationCancelAction),
                  app.l10n.creationCancelAction,
                );
              }
              app.observer.observe(flow.table, hold: true);
              await _submit(tester, app, flow);
              if (flow == _Flow.intention) {
                await tester.tap(_key('intention-editor-close'));
                await _until(
                  tester,
                  () =>
                      _key('intention-editor-close-discard')
                          .evaluate()
                          .isNotEmpty,
                );
                await tester.pump(const Duration(milliseconds: 400));
                final explanation = find.text(
                  app.l10n.editorCloseSavingMessage,
                );
                await _expectReadableExplanation(tester, explanation);
                expect(
                  find.bySemanticsLabel(app.l10n.editorCloseSavingMessage),
                  findsOneWidget,
                );
                final leave = _key('intention-editor-close-discard');
                await _reveal(tester, leave);
                _expectAction(
                  tester,
                  leave,
                  app.l10n.editorCloseSavingLeaveAction,
                );
                tester.semantics.tap(
                  find.semantics.byPredicate(
                    (node) => node.id == tester.getSemantics(leave).id,
                  ),
                );
              } else {
                final leave = find.widgetWithText(
                  TextButton,
                  app.l10n.creationLeaveAction,
                );
                await _reveal(tester, leave);
                await tester.pump();
                final label = find.bySemanticsLabel(
                  app.l10n.creationLeaveAction,
                );
                _expectAction(tester, label, app.l10n.creationLeaveAction);
                expect(
                  tester.getSemantics(label).getSemanticsData().hint,
                  app.l10n.creationSavingContinues,
                );
                final explanation = find.text(app.l10n.creationSavingContinues);
                await _reveal(tester, explanation);
                await tester.pump();
                expect(explanation.hitTestable(), findsOneWidget);
                await _expectReadableExplanation(tester, explanation);
                await _reveal(tester, leave);
                tester.semantics.tap(
                  find.semantics.byPredicate(
                    (node) => node.id == tester.getSemantics(label).id,
                  ),
                );
              }
              await _until(
                tester,
                () => app.router.current.matchId == history.routes.last.matchId,
              );
              await tester.pumpAndSettle();
              history.expectRestored(tester, app.router);
              app.observer.release();
              await _until(
                tester,
                () => _key('graph-operation-message').evaluate().isNotEmpty,
              );
              await tester.pump(const Duration(milliseconds: 300));
              final message = _key('graph-operation-message');
              expect(message.hitTestable(), findsOneWidget);
              final panel = tester.getRect(find.byType(AppNavigationBar));
              expect(
                tester.getRect(message).bottom,
                lessThanOrEqualTo(panel.top),
              );
              for (final paragraph in tester.renderObjectList<RenderParagraph>(
                find.descendant(of: message, matching: find.byType(RichText)),
              )) {
                expect(paragraph.didExceedMaxLines, isFalse);
              }
              history.expectRestored(tester, app.router);
              expect(app.observer.attempts, 1);
              expect(tester.takeException(), isNull);
            } finally {
              semantics.dispose();
            }
          },
        );
      }
    }
  }
}

Future<void> _expectReadableExplanation(
  WidgetTester tester,
  Finder text,
) async {
  for (final paragraph in tester.renderObjectList<RenderParagraph>(
    find.descendant(of: text, matching: find.byType(RichText)),
  )) {
    expect(paragraph.didExceedMaxLines, isFalse);
  }
  await Scrollable.ensureVisible(tester.element(text), alignment: 0);
  await tester.pump();
  expect(tester.getRect(text).top, greaterThanOrEqualTo(0));
  await Scrollable.ensureVisible(tester.element(text), alignment: 1);
  await tester.pump();
  expect(
    tester.getRect(text).bottom,
    lessThanOrEqualTo(
      tester.view.physicalSize.height - tester.view.viewInsets.bottom,
    ),
  );
}

void _expectAction(WidgetTester tester, Finder finder, String label) {
  expect(finder.hitTestable(), findsOneWidget);
  final data = tester.getSemantics(finder).getSemanticsData();
  expect([data.label, data.tooltip], contains(label));
  expect(data.flagsCollection.isButton, isTrue);
  expect(data.hasAction(SemanticsAction.tap), isTrue);
}
