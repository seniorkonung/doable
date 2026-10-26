import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/design_system/components/path_glyph.dart';
import 'package:doable/src/design_system/components/sheet.dart';
import 'package:doable/src/design_system/components/top_bar.dart';
import 'package:doable/src/design_system/doable_theme.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_purpose.dart';
import 'package:doable/src/intention/presentation/picker/intention_picker_purpose_sheet.dart';
import 'package:doable/src/intention/presentation/picker/intention_picker_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../catalog/catalog_reconciliation_test_support.dart';
import '../catalog/catalog_test_support.dart';

void main() {
  for (final locale in [const Locale('ru'), const Locale('en')]) {
    final ru = locale.languageCode == 'ru';
    final title = ru ? 'Выбор намерения' : 'Choose an intention';
    final sheetTitle = ru ? 'Что вы выбираете' : 'What you are choosing';
    final back = ru ? 'Вернуться к списку' : 'Back to the list';

    testWidgets(
      '${locale.languageCode}: лист напоминает назначение и не меняет поиск',
      (tester) async {
        final h = await _open(tester, locale);
        await tester.enterText(
          find.byKey(const ValueKey('daily-choice-source-filter')),
          'бег',
        );
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump();
        h.repository.complete(
          h.repository.queries.length - 1,
          ResultSuccess(
            IntentionCatalogFirstPage(
              items: [
                for (var i = 20; i > 0; i--)
                  testSummary(index: i, title: 'Бегать $i'),
              ],
              totalCount: 20,
              typeCounts: null,
              nextCursor: null,
              revision: const TestCatalogRevision(1),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final list = find.byKey(
          const PageStorageKey<String>('daily-choice-source-list'),
        );
        await tester.drag(list, const Offset(0, -400));
        await tester.pumpAndSettle();
        final pixels = _position(tester, list).pixels;
        expect(pixels, greaterThan(0));
        final queries = h.repository.queries.length;

        await tester.tap(find.text(_subtitle));
        await tester.pumpAndSettle();
        expect(find.text(sheetTitle), findsOneWidget);
        await tester.tap(find.text(back));
        await tester.pumpAndSettle();

        expect(find.byType(Sheet), findsNothing);
        expect(find.widgetWithText(TextField, 'бег'), findsOneWidget);
        expect(h.repository.queries, hasLength(queries));
        expect(_position(tester, list).pixels, pixels);
      },
    );

    testWidgets(
      '${locale.languageCode}: подзаголовок под заголовком открывает лист со '
      'строкой, телом и «Вернуться к списку», а кнопка отмечена раскрытой, '
      'пока лист открыт',
      (tester) async {
        final semantics = tester.ensureSemantics();
        await _open(tester, locale);
        final subtitle = find.text(_subtitle);
        expect(
          tester.getRect(subtitle).top,
          greaterThanOrEqualTo(tester.getRect(find.text(title)).bottom),
        );

        void expectButton({required bool expanded}) => expect(
          tester.getSemantics(subtitle),
          isSemantics(
            label: ru
                ? '$title. $_subtitle. Показать, что выбирается'
                : '$title. $_subtitle. Show what you are choosing',
            isButton: true,
            hasTapAction: true,
            hasExpandedState: true,
            isExpanded: expanded,
          ),
        );

        expectButton(expanded: false);
        await tester.tap(subtitle);
        await _settleSheet(tester);
        expectButton(expanded: true);
        final sheet = find.byType(Sheet);
        for (final text in [sheetTitle, _sheetLine, _body, back]) {
          expect(
            find.descendant(of: sheet, matching: find.text(text)),
            findsOneWidget,
          );
        }

        await tester.tap(find.text(back));
        await _settleSheet(tester);
        expect(sheet, findsNothing);
        expectButton(expanded: false);
        semantics.dispose();
      },
    );
  }

  for (final (mark, shape) in [
    (TopBarPurposeMark.sourceField, PathGlyphShape.diamond),
    (TopBarPurposeMark.relatedField, PathGlyphShape.ring),
  ]) {
    testWidgets('отметка ${mark.name} из описания назначения стоит в шапке '
        'перед подзаголовком: ${shape.name}', (tester) async {
      await _open(tester, const Locale('ru'), subtitleMark: mark);

      final glyph = find.descendant(
        of: find.byType(TopBar),
        matching: find.byType(PathGlyph),
      );
      expect(tester.widget<PathGlyph>(glyph).shape, shape);
      expect(
        tester.getRect(glyph).right,
        lessThan(tester.getRect(find.text(_subtitle)).left),
      );
    });
  }
}

const _subtitle = 'Новый поток: исходное';
const _sheetLine = 'Новый поток, от начала';
const _body = 'Шаги потока';

/// Выдача ещё не получена и её индикатор вращается, поэтому ждём только
/// переход листа.
Future<void> _settleSheet(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

ScrollPosition _position(WidgetTester tester, Finder list) => tester
    .state<ScrollableState>(
      find.descendant(of: list, matching: find.byType(Scrollable)),
    )
    .position;

Future<({ProviderContainer container, ControlledCatalogRepository repository})>
_open(
  WidgetTester tester,
  Locale locale, {
  TopBarPurposeMark? subtitleMark,
}) async {
  tester.view
    ..physicalSize = const Size(390, 844)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final repository = ControlledCatalogRepository();
  final container = reconciliationCatalogContainer(repository);
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: locale,
        theme: doableTheme(Brightness.light),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: IntentionPickerView(
          purpose: SelectDailyChoiceSource(session: IntentionSearchSession()),
          purposeDescription: IntentionPickerPurposeDescription(
            subtitle: _subtitle,
            sheetLine: _sheetLine,
            buildSheetBody: (_) => const Text(_body),
            subtitleMark: subtitleMark,
          ),
          closeLabel: 'Закрыть поиск',
          emptyScopeMessage: 'Выбрать не из чего',
          onClose: () {},
          onPick: (_) {},
          onOpenDetails: (_) {},
        ),
      ),
    ),
  );
  await tester.pump();
  return (container: container, repository: repository);
}
