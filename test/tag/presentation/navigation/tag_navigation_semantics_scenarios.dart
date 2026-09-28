part of 'tag_navigation_page_test.dart';

void _registerNavigationSemanticsScenarios() {
  for (final locale in ['ru', 'en']) {
    for (final failure in [
      const TaggedEntitiesUnavailableFailure(),
      const TaggedEntitiesCorruptionFailure(),
      const TaggedEntitiesUnexpectedFailure(),
      const TaggedEntitiesInvalidCursor(),
    ]) {
      testWidgets(
        'причина отказа и допустимые действия доступны при масштабе 3 на $locale: ${failure.runtimeType}',
        (tester) async {
          tester.view.physicalSize = const Size(360, 640);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final semantics = tester.ensureSemantics();
          try {
            final reads = _Reads();
            addTearDown(reads.dispose);
            await _pumpPage(tester, reads, locale: locale, textScale: 3);
            final l10n = AppLocalizations.of(
              tester.element(find.byType(TagNavigationPage)),
            );
            await _expectNavigationStatusSemantics(
              tester,
              l10n.tagNavigationLoading,
            );
            reads.fail(0, failure);
            await tester.pumpAndSettle();
            final message = switch (failure) {
              TaggedEntitiesUnavailableFailure() =>
                l10n.tagNavigationUnavailable,
              TaggedEntitiesCorruptionFailure() => l10n.tagNavigationCorruption,
              TaggedEntitiesUnexpectedFailure() => l10n.tagNavigationUnexpected,
              TaggedEntitiesInvalidCursor() => l10n.tagNavigationInvalidCursor,
              _ => throw StateError('Непредусмотренный отказ фикстуры'),
            };
            await _expectNavigationStatusSemantics(tester, message);
            if (failure is TaggedEntitiesUnavailableFailure) {
              final retry = find.widgetWithText(
                OutlinedButton,
                l10n.commonRetry,
              );
              await _scrollTo(tester, retry);
              final node = tester.getSemantics(retry);
              expect(node.label, l10n.commonRetry);
              expect(node.flagsCollection.isButton, isTrue);
              expect(
                node.getSemanticsData().hasAction(SemanticsAction.tap),
                isTrue,
              );
              await tester.tap(retry);
              await tester.pump();
              expect(reads.queries, hasLength(2));
              reads.page(1, []);
              await tester.pumpAndSettle();
              await _expectNavigationStatusSemantics(
                tester,
                l10n.tagNavigationEmptyActive,
              );
            } else {
              expect(find.byType(OutlinedButton), findsNothing);
            }
            expect(tester.takeException(), isNull);
          } finally {
            semantics.dispose();
          }
        },
      );
    }

    testWidgets(
      'пустые охваты и отсутствие тега различимы при масштабе 3 на $locale',
      (tester) async {
        tester.view.physicalSize = const Size(360, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final semantics = tester.ensureSemantics();
        try {
          final reads = _Reads();
          addTearDown(reads.dispose);
          await _pumpPage(tester, reads, locale: locale, textScale: 3);
          final tag = Tag(
            id: _tag.id,
            name: TagName.fromInput('Длинное название 🏷️ ' * 10),
          );
          reads.page(0, [], tag: tag);
          await tester.pumpAndSettle();
          final l10n = AppLocalizations.of(
            tester.element(find.byType(TagNavigationPage)),
          );
          await _expectNavigationStatusSemantics(
            tester,
            l10n.tagNavigationEmptyActive,
          );
          final archived = _scope(TaggedEntitiesScope.archived);
          await tester.scrollUntilVisible(archived, -300, maxScrolls: 100);
          await tester.pumpAndSettle();
          await tester.tap(archived);
          await tester.pump();
          reads.page(1, [], tag: tag);
          await tester.pumpAndSettle();
          await _expectNavigationStatusSemantics(
            tester,
            l10n.tagNavigationEmptyArchived,
          );
          reads.watch.add(
            const TagReadSuccess(
              GraphSnapshot(value: null, revision: _Revision(2)),
            ),
          );
          await tester.pumpAndSettle();
          await _expectNavigationStatusSemantics(tester, l10n.tagNotFound);
          expect(
            find.text(l10n.tagNavigationTag(tag.name.value)),
            findsNothing,
          );
          for (final scope in TaggedEntitiesScope.values) {
            await tester.scrollUntilVisible(
              _scope(scope),
              -300,
              maxScrolls: 100,
            );
            await tester.pumpAndSettle();
            final node = tester.getSemantics(_scope(scope));
            expect(node.flagsCollection.isEnabled, Tristate.isFalse);
            expect(
              node.getSemanticsData().hasAction(SemanticsAction.tap),
              isFalse,
            );
          }
          expect(find.byType(OutlinedButton), findsNothing);
          expect(tester.takeException(), isNull);
        } finally {
          semantics.dispose();
        }
      },
    );

    testWidgets('семантический и клавиатурный обход навигации на $locale', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final semantics = tester.ensureSemantics();
      try {
        final reads = _Reads();
        addTearDown(reads.dispose);
        await _pumpPage(tester, reads, locale: locale);
        final items = [
          _intention(1),
          _relation(101),
          _relation(102, type: LongTermRelationType.can),
        ];
        final cursor = _Cursor();
        reads.page(0, items, cursor: cursor);
        await tester.pumpAndSettle();
        final l10n = AppLocalizations.of(
          tester.element(find.byType(TagNavigationPage)),
        );
        final active = _scope(TaggedEntitiesScope.active);
        final archived = _scope(TaggedEntitiesScope.archived);
        final more = find.widgetWithText(
          OutlinedButton,
          l10n.tagNavigationLoadMore,
        );
        final labels = _navigationSemanticLabels(tester);
        final expectedLabels = [
          l10n.catalogScopeActive,
          l10n.catalogScopeArchived,
          for (final item in items) tester.getSemantics(_row(item)).label,
          l10n.tagNavigationLoadMore,
        ];
        var previousIndex = -1;
        for (final label in expectedLabels) {
          final index = labels.indexWhere((value) => value == label);
          expect(
            index,
            greaterThan(previousIndex),
            reason: 'Порядок обхода: $label',
          );
          previousIndex = index;
        }
        for (final item in items) {
          final node = tester.getSemantics(_row(item));
          expect(node.flagsCollection.isButton, isTrue);
          expect(node.hint, l10n.tagNavigationOpenDetails);
          expect(
            node.getSemanticsData().hasAction(SemanticsAction.tap),
            isTrue,
          );
        }
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pump();
        for (final control in [active, archived, ...items.map(_row), more]) {
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pumpAndSettle();
          final focusedWidget =
              FocusManager.instance.primaryFocus!.context!.widget;
          expect(
            find.ancestor(
              of: find.byWidget(focusedWidget),
              matching: control,
              matchRoot: true,
            ),
            findsOneWidget,
            reason: 'Клавиатурный фокус: $control',
          );
        }
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        expect(reads.queries, hasLength(2));
        expect(reads.queries.last.cursor, same(cursor));
        reads.page(1, [_intention(2)]);
        await tester.pumpAndSettle();
        expect(_row(_intention(2)), findsOneWidget);
        expect(find.text(l10n.tagNavigationAllShown), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    });
  }
}

Future<void> _expectNavigationStatusSemantics(
  WidgetTester tester,
  String message,
) async {
  final text = find.text(message);
  await tester.scrollUntilVisible(text, 300, maxScrolls: 100);
  await tester.pump();
  expect(_navigationSemanticLabels(tester), contains(message));
  final region = find.ancestor(
    of: text,
    matching: find.byWidgetPredicate(
      (widget) => widget is Semantics && widget.properties.liveRegion == true,
    ),
  );
  expect(tester.getSemantics(region).flagsCollection.isLiveRegion, isTrue);
}

List<String> _navigationSemanticLabels(WidgetTester tester) {
  final labels = <String>[];
  void visit(SemanticsNode node) {
    if (node.label.isNotEmpty) labels.add(node.label);
    for (final child in node.debugListChildrenInOrder(
      DebugSemanticsDumpOrder.traversalOrder,
    )) {
      visit(child);
    }
  }

  visit(
    tester.binding.renderViews.first.owner!.semanticsOwner!.rootSemanticsNode!,
  );
  return labels;
}
