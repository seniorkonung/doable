import 'dart:async';
import 'dart:math' as math;

import 'package:doable/src/action/application/action_details.dart';
import 'package:doable/src/action/domain/action_priority.dart';
import 'package:doable/src/action/presentation/panel/action_panel.dart';
import 'package:doable/src/design_system/components/action_head.dart';
import 'package:doable/src/design_system/components/sheet.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/shared/domain/calendar_date.dart';
import 'package:doable/src/shared/presentation/local_day/local_date_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/action_panel_fixture.dart';
import '../../../support/controlled_local_date.dart';
import '../../../support/ordinary_page_test_app.dart';

void main() {
  for (final (name, expands) in const [
    ('компактном', false),
    ('полном', true),
  ]) {
    testWidgets('при предельных названиях, крупном шрифте и на низком экране '
        'весь текст панели достижим без обрезки в $name размере', (
      tester,
    ) async {
      await _useExtremeScreen(tester);
      final semantics = tester.ensureSemantics();
      await _openPanel(tester, _extremeDetails());
      if (expands) {
        await tester.tap(_expand);
        await tester.pumpAndSettle();
      }

      await _expectWholeTextReachable(tester, [
        _maxTitle('основа'),
        _maxTitle('действие'),
        _maxDescription,
        'Дата',
        '8 окт. 2025',
        'Время',
        'Весь день',
        'Приоритет',
        'P1',
        'P2',
        'P3',
        'P4',
        'Создано 6 окт.',
      ]);
      semantics.dispose();
    });
  }

  testWidgets('палец вверх по высокой шапке раскрывает панель, затем шапка '
      'уходит вместе с телом, а ручка стоит на месте', (tester) async {
    await _useExtremeScreen(tester);
    final semantics = tester.ensureSemantics();
    await _openPanel(tester, _extremeDetails());
    final compact = tester.getRect(_sheet);
    final handleOffset = tester.getTopLeft(_expand).dy - compact.top;
    expect(_headerHeight(tester), greaterThan(_list(tester).height / 2));

    final gesture = await tester.startGesture(
      Offset(compact.center.dx, tester.getTopLeft(_head).dy + 60),
    );
    for (var move = 0; move < 40; move++) {
      await gesture.moveBy(const Offset(0, -20));
      await tester.pump();
      final scrolled = _body(tester).pixels;
      if (scrolled > 0) expect(tester.getTopLeft(_sheet).dy, _statusBar);
      expect(
        tester.getTopLeft(_head).dy,
        closeTo(_list(tester).top - scrolled, 0.01),
      );
    }
    expect(_body(tester).pixels, greaterThan(0));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(tester.getTopLeft(_sheet).dy, _statusBar);
    expect(_headerHeight(tester), greaterThan(_list(tester).height / 2));
    expect(tester.getTopLeft(_collapse).dy - _statusBar, handleOffset);
    expect(_collapse.hitTestable(), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('шапка не выше порога остаётся на месте при прокрутке тела', (
    tester,
  ) async {
    _useScreen(tester, const Size(390, 844));
    final semantics = tester.ensureSemantics();
    await _openPanel(tester, actionDetailsFixture(description: _longText));
    await tester.tap(_expand);
    await tester.pumpAndSettle();
    final head = tester.getTopLeft(_head);
    expect(_headerHeight(tester), lessThan(_list(tester).height / 2));

    await tester.dragFrom(_list(tester).center, const Offset(0, -300));
    await tester.pumpAndSettle();

    expect(_body(tester).pixels, greaterThan(0));
    expect(tester.getTopLeft(_head), head);
    semantics.dispose();
  });

  testWidgets('раскрытие панели через порог закрепляет шапку', (tester) async {
    _useScreen(tester, const Size(390, 1000));
    final semantics = tester.ensureSemantics();
    await _openPanel(
      tester,
      actionDetailsFixture(
        title: _maxTitle('действие'),
        rootTitle: _maxTitle('основа'),
      ),
    );
    expect(_headerHeight(tester), greaterThan(_list(tester).height / 2));
    final compactTop = tester.getTopLeft(_head).dy;
    _body(tester).jumpTo(40);
    await tester.pump();
    expect(tester.getTopLeft(_head).dy, compactTop - 40);
    _body(tester).jumpTo(0);
    await tester.pump();

    await tester.tap(_expand);
    await tester.pumpAndSettle();

    expect(_headerHeight(tester), lessThan(_list(tester).height / 2));
    final fullTop = tester.getTopLeft(_head).dy;
    _body(tester).jumpTo(40);
    await tester.pump();
    expect(tester.getTopLeft(_head).dy, fullTop);
    semantics.dispose();
  });
}

const _statusBar = 24.0;

/// Название наибольшей допустимой длины: 255 графем.
String _maxTitle(String word) =>
    '${'$word ${'слово ' * 43}'.substring(0, 254)}я';

final _maxDescription = List.filled(120, 'строка описания').join(' ');

final _longText = List.filled(300, 'слово').join(' ');

final _sheet = find.byType(Sheet);

// Прокрученная шапка уходит за край списка, поэтому ищется и за ним.
final _head = find.byType(ActionHead, skipOffstage: false);
final _expand = find.bySemanticsLabel('Раскрыть панель действия');
final _collapse = find.bySemanticsLabel('Свернуть панель действия');

final _listFinder = find.descendant(
  of: _sheet,
  matching: find.byType(CustomScrollView),
);

Rect _list(WidgetTester tester) => tester.getRect(_listFinder);

ScrollPosition _body(WidgetTester tester) => tester
    .state<ScrollableState>(
      find.descendant(of: _sheet, matching: find.byType(Scrollable)).first,
    )
    .position;

double _headerHeight(WidgetTester tester) =>
    tester.getBottomLeft(_head).dy - tester.getTopLeft(_head).dy;

/// Экран ниже границы поддержки 360×720, но выше компактного предела, поэтому
/// у панели остаются оба размера. Шрифт — наибольший системный на Android.
Future<void> _useExtremeScreen(WidgetTester tester) async {
  _useScreen(tester, const Size(360, 640));
  tester.view
    ..padding = const FakeViewPadding(top: _statusBar, bottom: 48)
    ..viewPadding = const FakeViewPadding(top: _statusBar, bottom: 48);
  tester.platformDispatcher.textScaleFactorTestValue = 2;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  // Переносы и ширина пилюль зависят от настоящего шрифта.
  await (FontLoader('Inter')..addFont(
        rootBundle.load('lib/src/design_system/fonts/InterVariable.ttf'),
      ))
      .load();
}

void _useScreen(WidgetTester tester, Size size) {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

List<RenderParagraph> _paragraphs(WidgetTester tester, Finder of) => [
  for (final element
      in find
          .descendant(
            of: find.descendant(
              of: of,
              matching: find.byType(Text, skipOffstage: false),
              skipOffstage: false,
            ),
            matching: find.byType(RichText, skipOffstage: false),
            skipOffstage: false,
          )
          .evaluate())
    element.renderObject! as RenderParagraph,
];

Rect _rectOf(RenderParagraph paragraph) => MatrixUtils.transformRect(
  paragraph.getTransformTo(null),
  Offset.zero & paragraph.size,
);

/// Прокручивает тело шагами, не больше видимой части, и проверяет, что каждый
/// текст открылся по всей высоте. Текст в шапке виден в области списка, а
/// текст тела — только под шапкой: закреплённая шапка его закрывает.
Future<void> _expectWholeTextReachable(
  WidgetTester tester,
  List<String> texts,
) async {
  final body = _body(tester);
  body.jumpTo(0);
  await tester.pump();
  final paragraphs = _paragraphs(tester, _listFinder);
  expect(
    paragraphs.map((paragraph) => paragraph.text.toPlainText()),
    containsAll(texts),
  );
  final inHeader = _paragraphs(tester, _head).toSet();
  final reached = {for (final paragraph in paragraphs) paragraph: 0.0};
  final step = _list(tester).height / 2;
  for (var pixels = 0.0; ; pixels += step) {
    body.jumpTo(math.min(pixels, body.maxScrollExtent));
    await tester.pump();
    final list = _list(tester);
    final headerBottom = tester.getBottomLeft(_head).dy;
    for (final paragraph in paragraphs) {
      final rect = _rectOf(paragraph);
      final text = paragraph.text.toPlainText();
      expect(rect.left, greaterThanOrEqualTo(list.left), reason: text);
      expect(rect.right, lessThanOrEqualTo(list.right), reason: text);
      final top = math.max(
        rect.top,
        inHeader.contains(paragraph)
            ? list.top
            : math.max(list.top, headerBottom),
      );
      final bottom = math.min(rect.bottom, list.bottom);
      if (bottom > top && top - rect.top <= reached[paragraph]!) {
        reached[paragraph] = math.max(reached[paragraph]!, bottom - rect.top);
      }
    }
    if (body.pixels >= body.maxScrollExtent) break;
  }
  for (final paragraph in paragraphs) {
    final text = paragraph.text.toPlainText();
    final width = paragraph.size.width;
    expect(
      reached[paragraph],
      closeTo(paragraph.size.height, 0.01),
      reason: text,
    );
    expect(paragraph.didExceedMaxLines, isFalse, reason: text);
    expect(
      paragraph.size.height,
      greaterThanOrEqualTo(paragraph.getMaxIntrinsicHeight(width)),
      reason: text,
    );
    expect(
      width,
      greaterThanOrEqualTo(paragraph.getMinIntrinsicWidth(double.infinity)),
      reason: text,
    );
  }
  body.jumpTo(0);
  await tester.pump();
}

/// Открывает панель над страницей и выдаёт ей [details].
Future<void> _openPanel(WidgetTester tester, ActionDetails details) async {
  final repository = ActionPanelRepository();
  addTearDown(repository.dispose);
  final localDate = ControlledLocalDate(CalendarDate.fromParts(2026, 10, 8));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        personalGraphRepositoryProvider.overrideWith((ref) => repository),
        localDateSourceProvider.overrideWithValue(localDate.read),
      ],
      child: OrdinaryPageTestApp(
        locale: const Locale('ru'),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () =>
                  unawaited(showActionPanel(context, actionIdOf(1))),
              child: const Text('Открыть'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.tap(find.text('Открыть'));
  await tester.pump();
  repository.emit(details);
  await tester.pumpAndSettle();
}

/// Действие, в котором каждый текст панели занимает наибольшее место:
/// предельные названия и описание, дата с годом.
ActionDetails _extremeDetails() => actionDetailsFixture(
  rootTitle: _maxTitle('основа'),
  title: _maxTitle('действие'),
  description: _maxDescription,
  date: CalendarDate.fromParts(2025, 10, 8),
  priority: ActionPriority.p1,
);
