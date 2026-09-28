part of 'tag_catalog_search_page_test.dart';

void _registerSearchRecoveryScenarios() {
  for (final (description, target) in _modes) {
    for (final language in ['ru', 'en']) {
      testWidgets(
        '$description, $language: совместные ошибки и повтор доступны с клавиатурой и текстом 2.5',
        (tester) async {
          tester.view.physicalSize = const Size(420, 900);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final repository = await _pumpCatalog(
            tester,
            target: target,
            language: language,
            scale: 2.5,
          );
          final l10n = _localizations(tester);
          final work = _tag(1, 'Работа');
          final home = _tag(2, 'Дом');
          final forHome = _tag(3, 'Для дома');
          repository.complete([work, home, forHome], assignedIds: {home.id});
          await tester.pumpAndSettle();
          if (target != null) {
            await tester.tap(_row(work));
            await tester.pump();
          }
          tester.view.viewInsets = const FakeViewPadding(bottom: 300);
          await tester.enterText(_search, 'дом');
          await tester.pumpAndSettle();
          const invalid = 'работ\udc00';
          await tester.enterText(_search, invalid);
          await tester.pumpAndSettle();
          final input = tester.widget<TextField>(_search).controller!;
          final editingValue = input.value;
          final editable = tester.state<EditableTextState>(_editable);

          await _beginRefresh(tester, repository);
          repository.reads.last.complete(
            const TagCatalogError(TagCatalogUnavailableFailure()),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(tester.getRect(_list).height, greaterThan(0));
          expect(_loaded(tester, target).freshness, TagCatalogFreshness.stale);
          expect(input.value, editingValue);
          expect(find.text(l10n.tagCatalogNoMatches), findsNothing);
          for (final message in [
            l10n.tagCatalogInvalidSearch,
            l10n.tagCatalogUnavailable,
          ]) {
            await _readSearchMessage(tester, message);
          }
          for (final tag in [home, forHome]) {
            await _reachSearchElement(tester, _row(tag));
            final tile = tester.widget<ListTile>(
              find.descendant(of: _row(tag), matching: find.byType(ListTile)),
            );
            expect(tile.onTap, isNull);
            expect(tile.trailing, isNull);
          }
          if (target != null) {
            expect(_loaded(tester, target).selection.id, work.id);
            expect(
              find.descendant(of: _selected, matching: find.text('Рабочее')),
              findsOneWidget,
            );
            expect(_assignment(tester, home), l10n.tagCatalogAssigned);
            expect(tester.widget<FilledButton>(_assign).onPressed, isNull);
            expect(_assign.hitTestable(), findsOneWidget);
            expect(tester.getRect(_assign).bottom, lessThanOrEqualTo(600));
          }
          final retry = find.text(l10n.commonRetry, skipOffstage: false);
          await _reachSearchElement(tester, retry);
          final readsBeforeRetry = repository.reads.length;
          await tester.tap(retry);
          await tester.pump();
          expect(repository.reads.length, readsBeforeRetry + 1);
          expect(tester.testTextInput.isVisible, isTrue);
          expect(tester.view.viewInsets.bottom, 300);
          expect(editable.widget.focusNode.hasFocus, isTrue);

          final renamed = _tag(1, 'Рабочее');
          final updatedHome = _tag(2, 'Дом обновлённый');
          repository.complete(
            [renamed, updatedHome, forHome],
            revision: 2,
            assignedIds: {forHome.id},
          );
          await tester.pumpAndSettle();
          expect(
            _loaded(tester, target).freshness,
            TagCatalogFreshness.current,
          );
          expect(input.value, editingValue);
          expect(find.text(l10n.tagCatalogUnavailable), findsNothing);
          await _readSearchMessage(tester, l10n.tagCatalogInvalidSearch);
          for (final tag in [updatedHome, forHome]) {
            await _reachSearchElement(tester, _row(tag));
            expect(
              find.descendant(
                of: _row(tag),
                matching: find.text(tag.name.value),
              ),
              findsOneWidget,
            );
          }
          if (target != null) {
            expect(_loaded(tester, target).selection.id, work.id);
            expect(_assignment(tester, updatedHome), l10n.tagCatalogAvailable);
            expect(_assignment(tester, forHome), l10n.tagCatalogAssigned);
            expect(tester.widget<FilledButton>(_assign).onPressed, isNotNull);
            expect(_assign.hitTestable(), findsOneWidget);
            await tester.ensureVisible(
              find.descendant(of: _selected, matching: find.text('Рабочее')),
            );
            await tester.pumpAndSettle();
            expect(find.text('Рабочее').hitTestable(), findsOneWidget);
            expect(
              tester.getRect(find.text('Рабочее')).bottom,
              lessThanOrEqualTo(600),
            );
          }

          final readCounts = (
            repository.reads.length,
            repository.statusReads.length,
          );
          final commandCount = repository.commands.length;
          await _reachSearchElement(tester, _editable);
          await tester.tap(_editable);
          await tester.enterText(_search, 'раб');
          await tester.pumpAndSettle();
          expect(find.text(l10n.tagCatalogInvalidSearch), findsNothing);
          await _reachSearchElement(tester, _row(renamed));
          expect(_visibleNames(tester), ['Рабочее']);
          await _reachSearchElement(
            tester,
            find.byTooltip(l10n.tagCatalogClearSearch, skipOffstage: false),
          );
          await tester.tap(find.byTooltip(l10n.tagCatalogClearSearch));
          await tester.pumpAndSettle();
          expect(input.text, isEmpty);
          for (final tag in [renamed, updatedHome, forHome]) {
            await _reachSearchElement(tester, _row(tag));
          }
          expect((
            repository.reads.length,
            repository.statusReads.length,
          ), readCounts);
          expect(repository.commands.length, commandCount);
          expect(tester.testTextInput.isVisible, isTrue);
          expect(tester.view.viewInsets.bottom, 300);
          expect(tester.state<EditableTextState>(_editable), same(editable));
          expect(editable.widget.focusNode.hasFocus, isTrue);
          final create = find.byKey(const ValueKey('tag-catalog-create'));
          expect(create.hitTestable(), findsOneWidget);
          expect(tester.widget<IconButton>(create).onPressed, isNotNull);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}

Future<void> _readSearchMessage(WidgetTester tester, String message) async {
  final text = find.text(message, skipOffstage: false);
  await _reachSearchElement(tester, text);
  expect(tester.renderObject<RenderParagraph>(text).didExceedMaxLines, isFalse);
  await Scrollable.ensureVisible(tester.element(text), alignment: 0);
  await tester.pumpAndSettle();
  expect(
    tester.getRect(text).top,
    greaterThanOrEqualTo(tester.getRect(_list).top - 1),
  );
  await Scrollable.ensureVisible(tester.element(text), alignment: 1);
  await tester.pumpAndSettle();
  expect(
    tester.getRect(text).bottom,
    lessThanOrEqualTo(tester.getRect(_list).bottom + 1),
  );
}
