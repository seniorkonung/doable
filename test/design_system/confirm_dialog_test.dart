import 'dart:async';

import 'package:doable/src/design_system/components/button.dart';
import 'package:doable/src/design_system/components/confirm_dialog.dart';
import 'package:doable/src/design_system/components/sheet.dart';
import 'package:doable/src/design_system/doable_colors.dart';
import 'package:doable/src/design_system/doable_metrics.dart';
import 'package:doable/src/design_system/doable_shadows.dart';
import 'package:doable/src/design_system/doable_theme.dart';
import 'package:doable/src/design_system/doable_type.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final brightness in Brightness.values) {
    final theme = brightness == Brightness.light ? 'светлой' : 'тёмной';

    testWidgets('в $theme теме диалог стоит по центру в space-8 от краёв, а '
        'плоскость, тексты и действия следуют токенам', (tester) async {
      final colors = _colorsOf(brightness);
      final shadows = _shadowsOf(brightness);
      final dialog = _Dialog();
      _useScreen(tester);
      await tester.pumpWidget(dialog.app(brightness: brightness));

      await dialog.open(tester);

      final plane = tester.getRect(_plane);
      expect(plane.left, DoableMetrics.space8);
      expect(plane.right, _screen.width - DoableMetrics.space8);
      expect(plane.center.dy, _screen.height / 2);
      final decoration =
          tester.widget<DecoratedBox>(_plane).decoration as BoxDecoration;
      expect(decoration.color, colors.raised);
      expect(
        decoration.borderRadius,
        BorderRadius.circular(DoableMetrics.radiusXl),
      );
      expect(decoration.boxShadow, shadows.shadowFloat);
      expect(
        tester
            .widgetList<ModalBarrier>(find.byType(ModalBarrier))
            .map((barrier) => barrier.color),
        contains(colors.scrim),
      );

      final title = tester.getRect(find.text(_title));
      expect(title.top, plane.top + 22);
      expect(title.left, plane.left + DoableMetrics.space6);
      final titleStyle = tester.widget<Text>(find.text(_title)).style!;
      expect(titleStyle.fontSize, DoableType.title.fontSize);
      expect(titleStyle.fontWeight, DoableType.title.fontWeight);
      expect(titleStyle.color, colors.ink);

      final paragraph = tester.getRect(_paragraph);
      expect(paragraph.top, title.bottom + 6);
      expect(paragraph.left, plane.left + DoableMetrics.space6);
      final paragraphStyle = tester
          .renderObject<RenderParagraph>(_paragraph)
          .text
          .style!;
      expect(paragraphStyle.fontSize, DoableType.body.fontSize);
      expect(paragraphStyle.fontWeight, DoableType.body.fontWeight);
      expect(paragraphStyle.color, colors.muted);

      final cancel = tester.getRect(_pillOf('Отмена'));
      final delete = tester.getRect(_pillOf('Удалить'));
      expect(cancel.height, DoableMetrics.controlHeight);
      expect(delete.height, DoableMetrics.controlHeight);
      expect(delete.right, plane.right - DoableMetrics.space6);
      expect(delete.left - cancel.right, DoableMetrics.space2);
      expect(cancel.top, delete.top);
      // Плашки 40 стоят по центру строки действий 44, которая отстоит от
      // текста и нижнего края плоскости на space-4.
      expect(cancel.top, paragraph.bottom + DoableMetrics.space4 + 2);
      expect(plane.bottom - delete.bottom, DoableMetrics.space4 + 2);
      expect(_pillColorOf(tester, 'Отмена'), colors.fill);
      expect(_pillColorOf(tester, 'Удалить'), colors.accent);
    });

    testWidgets('в $theme теме название в тексте выделено цветом ink без '
        'смены начертания', (tester) async {
      final colors = _colorsOf(brightness);
      final dialog = _Dialog();
      _useScreen(tester);
      await tester.pumpWidget(dialog.app(brightness: brightness));

      await dialog.open(tester);

      final text = tester.renderObject<RenderParagraph>(_paragraph).text;
      expect(text.toPlainText(), 'Тег «спорт» будет удалён.');
      final spans = <TextSpan>[];
      text.visitChildren((span) {
        if (span is TextSpan && span.text != null) spans.add(span);
        return true;
      });
      final name = spans.singleWhere((span) => span.text == 'спорт');
      expect(name.style!.color, colors.ink);
      expect(name.style!.fontWeight, isNull);
      expect(
        spans.where((span) => span != name).map((span) => span.style),
        everyElement(isNull),
        reason: 'остальной текст наследует muted абзаца',
      );
    });
  }

  testWidgets('действие закрывает диалог и подтверждает', (tester) async {
    final dialog = _Dialog();
    _useScreen(tester);
    await tester.pumpWidget(dialog.app());
    await dialog.open(tester);

    await tester.tap(find.text('Удалить'));
    await tester.pumpAndSettle();

    expect(_plane, findsNothing);
    expect(dialog.result, completion(isTrue));
  });

  testWidgets('«Отмена» закрывает диалог без подтверждения', (tester) async {
    final dialog = _Dialog();
    _useScreen(tester);
    await tester.pumpWidget(dialog.app());
    await dialog.open(tester);

    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();

    expect(_plane, findsNothing);
    expect(dialog.result, completion(isFalse));
  });

  testWidgets('касание затемнения над листом отменяет и закрывает только '
      'диалог', (tester) async {
    final colors = _colorsOf(Brightness.light);
    final dialog = _Dialog();
    _useScreen(tester);
    await tester.pumpWidget(dialog.app());
    await dialog.open(tester, overSheet: true);

    final scrim = tester
        .widgetList<ModalBarrier>(find.byType(ModalBarrier))
        .lastWhere((barrier) => barrier.color == colors.scrim);
    expect(
      tester.getRect(find.byWidget(scrim)),
      Offset.zero & _screen,
      reason: 'затемнение диалога покрывает и лист',
    );

    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(_plane, findsNothing);
    expect(find.text(_sheetText), findsOneWidget);
    expect(dialog.result, completion(isFalse));
  });

  testWidgets('системное «назад» над листом отменяет и закрывает только '
      'диалог', (tester) async {
    final dialog = _Dialog();
    _useScreen(tester);
    await tester.pumpWidget(dialog.app());
    await dialog.open(tester, overSheet: true);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(_plane, findsNothing);
    expect(find.text(_sheetText), findsOneWidget);
    expect(dialog.result, completion(isFalse));
  });

  testWidgets('диалог объявляет себя маршрутом с названием по заголовку, а '
      'затемнение называет отмену', (tester) async {
    final semantics = tester.ensureSemantics();
    final dialog = _Dialog();
    _useScreen(tester);
    await tester.pumpWidget(dialog.app());
    await dialog.open(tester);

    expect(
      find.semantics.byPredicate(
        (node) =>
            node.label == _title &&
            node.flagsCollection.scopesRoute &&
            node.flagsCollection.namesRoute,
      ),
      findsOne,
    );
    expect(
      find.semantics.byPredicate(
        (node) => node.role == SemanticsRole.alertDialog,
      ),
      findsOne,
    );
    expect(
      find.semantics.byPredicate(
        (node) =>
            node.label == 'Отмена' &&
            node.getSemanticsData().hasAction(SemanticsAction.dismiss),
      ),
      findsOne,
    );
    for (final label in ['Отмена', 'Удалить']) {
      expect(
        tester.getSemantics(find.text(label)),
        isSemantics(label: label, isButton: true, hasTapAction: true),
      );
    }
    semantics.dispose();
  });

  testWidgets('с крупным шрифтом диалог растёт, а действия остаются '
      'доступны', (tester) async {
    final dialog = _Dialog();
    _useScreen(tester);
    await tester.pumpWidget(dialog.app());
    await dialog.open(tester);
    final regular = tester.getRect(_plane);
    Navigator.of(tester.element(_plane)).pop();
    await tester.pumpAndSettle();

    _useScreen(tester, textScale: 2);
    await tester.pumpWidget(dialog.app());
    await dialog.open(tester);

    final large = tester.getRect(_plane);
    expect(large.height, greaterThan(regular.height));
    expect(large.width, regular.width);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Удалить'));
    await tester.pumpAndSettle();
    expect(dialog.result, completion(isTrue));
  });
}

const _title = 'Удалить тег?';
const _sheetText = 'Содержимое листа';
const _screen = Size(390, 844);

/// Страница, с которой открывается диалог, и результат его показа.
final class _Dialog {
  late BuildContext _openerContext;
  late Future<bool> result;

  Widget app({Brightness brightness = Brightness.light}) => MaterialApp(
    theme: doableTheme(brightness),
    home: Scaffold(
      body: Builder(
        builder: (context) {
          _openerContext = context;
          return const SizedBox.expand();
        },
      ),
    ),
  );

  /// С [overSheet] диалог открывается из листа над страницей.
  Future<void> open(WidgetTester tester, {bool overSheet = false}) async {
    if (overSheet) {
      unawaited(
        showDoableSheet<void>(
          context: _openerContext,
          builder: (context, sheet) => Sheet(
            sheet,
            title: 'Лист',
            child: Builder(
              builder: (context) {
                _openerContext = context;
                return const Text(_sheetText);
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }
    result = showConfirmDialog(
      context: _openerContext,
      title: _title,
      text: const ConfirmDialogText(
        before: 'Тег «',
        name: 'спорт',
        after: '» будет удалён.',
      ),
      cancelLabel: 'Отмена',
      actionLabel: 'Удалить',
    );
    await tester.pumpAndSettle();
  }
}

final _plane = find.descendant(
  of: find.byType(Dialog),
  matching: find.byWidgetPredicate(
    (widget) =>
        widget is DecoratedBox &&
        widget.decoration is BoxDecoration &&
        (widget.decoration as BoxDecoration).boxShadow != null,
  ),
);

final _paragraph = find.byWidgetPredicate(
  (widget) => widget is RichText && widget.text.toPlainText().contains('спорт'),
);

Finder _pillOf(String label) => find.descendant(
  of: find.widgetWithText(Button, label),
  matching: find.byType(Material),
);

Color? _pillColorOf(WidgetTester tester, String label) =>
    tester.widget<Material>(_pillOf(label)).color;

void _useScreen(WidgetTester tester, {double textScale = 1}) {
  tester.view
    ..devicePixelRatio = 1
    ..physicalSize = _screen;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

DoableColors _colorsOf(Brightness brightness) => switch (brightness) {
  Brightness.light => DoableColors.light,
  Brightness.dark => DoableColors.dark,
};

DoableShadows _shadowsOf(Brightness brightness) => switch (brightness) {
  Brightness.light => DoableShadows.light,
  Brightness.dark => DoableShadows.dark,
};
