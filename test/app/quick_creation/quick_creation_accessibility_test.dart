import 'dart:async';
import 'dart:ui' show Tristate;

import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/main.dart';
import 'package:doable/src/app/app_runtime.dart';
import 'package:doable/src/app/navigation/app_destination.dart';
import 'package:doable/src/app/navigation/app_navigation_bar.dart';
import 'package:doable/src/app/quick_creation/quick_creation_button.dart';
import 'package:doable/src/app/quick_creation/quick_creation_mode.dart';
import 'package:doable/src/app/quick_creation/quick_creation_mode_presentation.dart';
import 'package:doable/src/app/routing/app_router_provider.dart';
import 'package:doable/src/app/routing/app_router.gr.dart';
import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/design_system/components/option_row.dart';
import 'package:doable/src/design_system/doable_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/in_memory_diagnostics_sink.dart';
import '../../support/in_memory_quick_creation_mode_store.dart';
import '../../support/app_root_pages.dart';

const _titles = {
  'ru': ['Новое намерение', 'Новая связь', 'Новый дневной выбор'],
  'en': ['New intention', 'New relation', 'New daily choice'],
};

// Размер экрана не меняет ветвление кода, поэтому берём телефонную ширину.
// Меняют путь только отступы, клавиатура и страница поверх
// корня; язык проверяет видимые названия.
const _phone = Size(400, 800);

final _cases = [
  (language: 'ru', size: _phone, safe: false, keyboard: 0.0, deep: false),
  (language: 'ru', size: _phone, safe: true, keyboard: 0.0, deep: false),
  (language: 'en', size: _phone, safe: true, keyboard: 260.0, deep: true),
];

void main() {
  for (final variant in _cases) {
    testWidgets('панель и меню доступны: ${variant.language}, '
        '${variant.size}, '
        'отступы ${variant.safe ? "24/32" : "0/0"}, '
        'клавиатура ${variant.keyboard}, '
        '${variant.deep ? "просмотр тегов" : "корень"}', (tester) async {
      final semantics = tester.ensureSemantics();
      tester.view.physicalSize = variant.size;
      tester.view.devicePixelRatio = 1;
      final safeTop = variant.safe ? 24.0 : 0.0;
      final safeBottom = variant.safe ? 32.0 : 0.0;
      tester.view.viewPadding = FakeViewPadding(
        top: safeTop,
        bottom: safeBottom,
      );
      tester.view.padding = FakeViewPadding(
        top: safeTop,
        bottom: variant.keyboard == 0 ? safeBottom : 0,
      );
      tester.view.viewInsets = FakeViewPadding(bottom: variant.keyboard);

      tester.platformDispatcher.localesTestValue = [Locale(variant.language)];
      addTearDown(tester.view.reset);

      addTearDown(tester.platformDispatcher.clearLocalesTestValue);
      final runtime = AppRuntime(
        quickCreationModeStore: InMemoryQuickCreationModeStore(),
        connectionFactory: openInMemoryLocalDatabase,
        diagnosticsSink: InMemoryDiagnosticsSink(),
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await runtime.shutdown();
      });
      await tester.pumpWidget(MainApp(runtime: runtime));
      await tester.pumpAndSettle();
      final ready = await runtime.bootstrap() as AppRuntimeReady;
      final router = ready.container.read(appRouterProvider);
      for (final destination in AppDestination.values) {
        await tester.tap(appNavigationDestination(destination));
        await tester.pumpAndSettle();
        _expectPanel(tester, destination);
      }
      if (variant.deep) {
        unawaited(router.push<void>(TagCatalogRoute()));
        await tester.pumpAndSettle();
        _expectPanel(tester, AppDestination.intentionGraph);
      }
      final history = [for (final route in router.stackData) route.matchId];
      final button = find.byType(QuickCreationButton);
      final localizations = AppLocalizations.of(tester.element(button));
      final language = variant.language == 'ru' ? 'ru' : 'en';
      expect(localizations.localeName, language);
      final titles = _titles[language]!;
      _expectButtonIcons(tester, QuickCreationMode.intention, variant.size);
      final visibleBottom =
          variant.size.height -
          (variant.keyboard == 0 ? safeBottom : variant.keyboard);

      for (final mode in QuickCreationMode.values) {
        final node = tester.getSemantics(button);
        final action = node
            .getSemanticsData()
            .customSemanticsActionIds!
            .map(CustomSemanticsAction.getAction)
            .whereType<CustomSemanticsAction>()
            .singleWhere(
              (action) => action.label == localizations.quickCreationChangeMode,
            );
        tester.semantics.customAction(
          find.semantics.byLabel(node.label),
          action,
        );
        await tester.pumpAndSettle();
        expect(find.byType(BottomSheet), findsOneWidget);
        expect(
          tester
              .widgetList<OptionRow>(find.byType(OptionRow))
              .map((row) => row.name),
          titles,
        );
        expect(appNavigationDestinations().hitTestable(), findsNothing);
        expect(find.semantics.byLabel(node.label), findsNothing);
        final title = find.text(titles[mode.index]);
        final row = find.widgetWithText(OptionRow, titles[mode.index]);
        await tester.ensureVisible(row);
        await tester.pumpAndSettle();
        final viewport = tester.getRect(
          find.descendant(
            of: find.byType(BottomSheet),
            matching: find.byType(SingleChildScrollView),
          ),
        );
        final available = Rect.fromLTRB(
          0,
          safeTop,
          variant.size.width,
          visibleBottom,
        );
        for (final element in [
          row,
          title,
          find.descendant(of: row, matching: find.byIcon(mode.icon)),
        ]) {
          _expectWithin(tester, element, viewport.intersect(available));
        }
        expect(
          tester.renderObject<RenderParagraph>(title).didExceedMaxLines,
          isFalse,
        );
        expect(
          tester.getSemantics(row).flagsCollection.isSelected,
          tester.widget<QuickCreationButton>(button).mode == mode
              ? Tristate.isTrue
              : Tristate.isFalse,
        );
        await tester.tap(row);
        await tester.pumpAndSettle();
        expect(find.byType(BottomSheet), findsNothing);
        expect(tester.widget<QuickCreationButton>(button).mode, mode);
        expect([for (final route in router.stackData) route.matchId], history);
        expect(router.hasPagelessTopRoute, isFalse);
        _expectPanel(tester, AppDestination.intentionGraph);
        _expectButtonIcons(tester, mode, variant.size);
        expect(tester.takeException(), isNull);
      }
      semantics.dispose();
    });
  }
}

void _expectWithin(WidgetTester tester, Finder element, Rect bounds) {
  final rect = tester.getRect(element);
  expect(rect.isEmpty, isFalse);
  expect(rect.left, greaterThanOrEqualTo(bounds.left - 0.01));
  expect(rect.top, greaterThanOrEqualTo(bounds.top - 0.01));
  expect(rect.right, lessThanOrEqualTo(bounds.right + 0.01));
  expect(rect.bottom, lessThanOrEqualTo(bounds.bottom + 0.01));
  expect(element.hitTestable(), findsOneWidget);
}

void _expectPanel(WidgetTester tester, AppDestination selected) {
  final bar = find.byType(AppNavigationBar);
  final context = tester.element(bar);
  final localizations = AppLocalizations.of(context);
  for (final destination in AppDestination.values) {
    final node = tester.getSemantics(appNavigationDestination(destination));
    final position = MaterialLocalizations.of(context)
        .tabLabel(tabIndex: destination.index + 1, tabCount: 3);
    expect(node.label, '${destination.title(localizations)}\n$position');
    expect(node.role, SemanticsRole.tab);
    expect(node.parent?.role, SemanticsRole.tabBar);
    expect(node.flagsCollection.isButton, isTrue);
    expect(
      node.flagsCollection.isSelected,
      destination == selected ? Tristate.isTrue : Tristate.isFalse,
    );
    _expectWithin(
      tester,
      appNavigationDestination(destination),
      tester.getRect(bar),
    );
  }
  final button = find.byType(QuickCreationButton);
  final mode = tester.widget<QuickCreationButton>(button).mode;
  final node = tester.getSemantics(button);
  expect(
    node.label,
    '${localizations.quickCreationLabel}, ${mode.title(localizations)}',
  );
  expect(node.hint, localizations.quickCreationLongPressHint);
  expect(node.flagsCollection.isButton, isTrue);
  expect(node.flagsCollection.isSelected, Tristate.none);
  expect(node.role, isNot(SemanticsRole.tab));
  expect(node.indexInParent, isNull);
  expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
  expect(node.getSemanticsData().hasAction(SemanticsAction.longPress), isTrue);
  expect(node.parent?.role, isNot(SemanticsRole.tabBar));
}

void _expectButtonIcons(
  WidgetTester tester,
  QuickCreationMode mode,
  Size screen,
) {
  final button = find.byType(QuickCreationButton);
  final rect = tester.getRect(button);
  expect(rect.width, greaterThanOrEqualTo(48));
  expect(rect.height, greaterThanOrEqualTo(48));
  _expectWithin(tester, button, tester.getRect(find.byType(AppNavigationBar)));
  for (final icon in [DoableIconData.plus, mode.miniIcon]) {
    final finder = find.descendant(
      of: button,
      matching: find.byWidgetPredicate(
        (widget) => widget is DoableIcon && widget.icon == icon,
      ),
    );
    _expectWithin(tester, finder, rect.intersect(Offset.zero & screen));
  }
  expect(
    find.descendant(of: button, matching: find.byType(Text)),
    findsNothing,
  );
}
