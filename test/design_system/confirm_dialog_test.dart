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

  for (final brightness in Brightness.values) {
    final theme = brightness == Brightness.light ? 'светлой' : 'тёмной';

    testWidgets('в $theme теме диалог действия, которое сохраняет данные, '
        'ставит quiet-кнопку отмены и основную кнопку в space-2 рядом, а '
        'предупреждение стоит вторым абзацем цветом ink', (tester) async {
      final colors = _colorsOf(brightness);
      final dialog = _Dialog(show: _showPreserving);
      _useScreen(tester);
      await tester.pumpWidget(dialog.app(brightness: brightness));

      await dialog.open(tester);

      final plane = tester.getRect(_plane);
      final title = tester.getRect(find.text(_preservingTitle));
      final paragraph = tester.getRect(_preservingParagraph);
      expect(paragraph.top, title.bottom + 6);
      final paragraphStyle = tester
          .renderObject<RenderParagraph>(_preservingParagraph)
          .text
          .style!;
      expect(paragraphStyle.color, colors.muted);

      final warning = tester.getRect(find.text(_warning));
      expect(warning.top, paragraph.bottom + DoableMetrics.space2);
      expect(warning.left, paragraph.left);
      final warningStyle = tester.widget<Text>(find.text(_warning)).style!;
      expect(warningStyle.fontSize, DoableType.body.fontSize);
      expect(warningStyle.color, colors.ink);

      final cancel = tester.getRect(_pillOf('Отмена'));
      final action = tester.getRect(_pillOf('Вернуть'));
      expect(cancel.height, DoableMetrics.controlHeight);
      expect(action.height, DoableMetrics.controlHeight);
      expect(action.right, plane.right - DoableMetrics.space6);
      expect(action.left - cancel.right, DoableMetrics.space2);
      expect(cancel.top, action.top);
      // Плашки 40 стоят по центру строки действий 44, которая отстоит от
      // предупреждения и нижнего края плоскости на space-4.
      expect(cancel.top, warning.bottom + DoableMetrics.space4 + 2);
      expect(plane.bottom - action.bottom, DoableMetrics.space4 + 2);
      expect(_pillColorOf(tester, 'Отмена'), colors.fill);
      expect(_pillColorOf(tester, 'Вернуть'), colors.ink);
      expect(_labelColorOf(tester, 'Вернуть'), colors.bg);
    });
  }

  testWidgets('без предупреждения диалог действия, которое сохраняет данные, '
      'не оставляет места под второй абзац', (tester) async {
    final dialog = _Dialog(
      show: (context) => _showPreserving(context, warning: null),
    );
    _useScreen(tester);
    await tester.pumpWidget(dialog.app());

    await dialog.open(tester);

    expect(find.text(_warning), findsNothing);
    final plane = tester.getRect(_plane);
    final paragraph = tester.getRect(_preservingParagraph);
    final action = tester.getRect(_pillOf('Вернуть'));
    expect(action.top, paragraph.bottom + DoableMetrics.space4 + 2);
    expect(plane.bottom - action.bottom, DoableMetrics.space4 + 2);
  });

  testWidgets('в диалоге действия, которое сохраняет данные, название в '
      'первом абзаце выделено цветом ink', (tester) async {
    final colors = _colorsOf(Brightness.light);
    final dialog = _Dialog(show: _showPreserving);
    _useScreen(tester);
    await tester.pumpWidget(dialog.app());

    await dialog.open(tester);

    final text = tester
        .renderObject<RenderParagraph>(_preservingParagraph)
        .text;
    expect(text.toPlainText(), 'Связь «Гулять» снова станет активной.');
    final spans = <TextSpan>[];
    text.visitChildren((span) {
      if (span is TextSpan && span.text != null) spans.add(span);
      return true;
    });
    expect(
      spans.singleWhere((span) => span.text == 'Гулять').style!.color,
      colors.ink,
    );
  });

  testWidgets('в диалоге действия, которое сохраняет данные, основная кнопка '
      'закрывает диалог и подтверждает', (tester) async {
    final dialog = _Dialog(show: _showPreserving);
    _useScreen(tester);
    await tester.pumpWidget(dialog.app());
    await dialog.open(tester);

    await tester.tap(find.text('Вернуть'));
    await tester.pumpAndSettle();

    expect(_plane, findsNothing);
    expect(dialog.result, completion(isTrue));
  });

  for (final (answer, respond)
      in <(String, Future<void> Function(WidgetTester))>[
        ('«Отмена»', (tester) => tester.tap(find.text('Отмена'))),
        ('касание затемнения', (tester) => tester.tapAt(const Offset(10, 10))),
        ('системное «назад»', (tester) => tester.binding.handlePopRoute()),
      ]) {
    testWidgets('в диалоге действия, которое сохраняет данные, $answer '
        'закрывает диалог без подтверждения', (tester) async {
      final dialog = _Dialog(show: _showPreserving);
      _useScreen(tester);
      await tester.pumpWidget(dialog.app());
      await dialog.open(tester, overSheet: true);

      await respond(tester);
      await tester.pumpAndSettle();

      expect(_plane, findsNothing);
      expect(find.text(_sheetText), findsOneWidget);
      expect(dialog.result, completion(isFalse));
    });
  }

  testWidgets('диалог действия, которое сохраняет данные, объявляет себя '
      'маршрутом с названием по заголовку, а затемнение называет отмену', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final dialog = _Dialog(show: _showPreserving);
    _useScreen(tester);
    await tester.pumpWidget(dialog.app());
    await dialog.open(tester);

    expect(
      find.semantics.byPredicate(
        (node) =>
            node.label == _preservingTitle &&
            node.flagsCollection.scopesRoute &&
            node.flagsCollection.namesRoute,
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
    for (final label in ['Отмена', 'Вернуть']) {
      expect(
        tester.getSemantics(find.text(label)),
        isSemantics(label: label, isButton: true, hasTapAction: true),
      );
    }
    semantics.dispose();
  });

  for (final brightness in Brightness.values) {
    final theme = brightness == Brightness.light ? 'светлой' : 'тёмной';

    testWidgets('в $theme теме диалог отмены изменений ставит текстовую '
        'кнопку отмены и основную кнопку в space-1 рядом, который выходит на '
        '8 правее текста', (tester) async {
      final colors = _colorsOf(brightness);
      final shadows = _shadowsOf(brightness);
      final dialog = _Dialog(show: _showDiscard);
      _useScreen(tester);
      await tester.pumpWidget(dialog.app(brightness: brightness));

      await dialog.open(tester);

      final plane = tester.getRect(_plane);
      expect(plane.left, DoableMetrics.space8);
      expect(plane.right, _screen.width - DoableMetrics.space8);
      final decoration =
          tester.widget<DecoratedBox>(_plane).decoration as BoxDecoration;
      expect(decoration.color, colors.raised);
      expect(decoration.boxShadow, shadows.shadowFloat);

      final title = tester.getRect(find.text(_discardTitle));
      expect(title.top, plane.top + 22);
      expect(title.left, plane.left + DoableMetrics.space6);
      expect(
        tester.widget<Text>(find.text(_discardTitle)).style!.color,
        colors.ink,
      );

      final paragraph = tester.getRect(_discardParagraph);
      expect(paragraph.top, title.bottom + 6);
      expect(paragraph.left, plane.left + DoableMetrics.space6);
      expect(
        paragraph.right,
        lessThanOrEqualTo(plane.right - DoableMetrics.space6),
      );
      final text = tester.renderObject<RenderParagraph>(_discardParagraph).text;
      expect(text.style!.fontSize, DoableType.body.fontSize);
      expect(text.style!.color, colors.muted);
      final styledSpans = <InlineSpan>[];
      text.visitChildren((span) {
        if (span != text && span.style != null) styledSpans.add(span);
        return true;
      });
      expect(styledSpans, isEmpty, reason: 'абзац без выделенного названия');

      final discard = tester.getRect(_pillOf(_discardLabel));
      final keep = tester.getRect(_pillOf(_keepLabel));
      expect(discard.height, DoableMetrics.controlHeight);
      expect(keep.height, DoableMetrics.controlHeight);
      expect(
        discard.width,
        tester.getRect(find.text(_discardLabel)).width + 2 * 14,
      );
      expect(
        keep.width,
        tester.getRect(find.text(_keepLabel)).width + 2 * DoableMetrics.space4,
      );
      expect(keep.right, plane.right - DoableMetrics.space6 + 8);
      expect(keep.left - discard.right, DoableMetrics.space1);
      expect(discard.top, keep.top);
      // Плашки 40 стоят по центру строки действий 44, которая отстоит от
      // текста и нижнего края плоскости на 14.
      expect(keep.top, paragraph.bottom + 14 + 2);
      expect(plane.bottom - keep.bottom, 14 + 2);
      expect(_pillColorOf(tester, _discardLabel), Colors.transparent);
      expect(_labelColorOf(tester, _discardLabel), colors.accent);
      expect(_pillColorOf(tester, _keepLabel), colors.ink);
      expect(_labelColorOf(tester, _keepLabel), colors.bg);
    });
  }

  testWidgets('в диалоге отмены изменений только текстовая кнопка отменяет '
      'работу', (tester) async {
    final dialog = _Dialog(show: _showDiscard);
    _useScreen(tester);
    await tester.pumpWidget(dialog.app());
    await dialog.open(tester);

    await tester.tap(find.text(_discardLabel));
    await tester.pumpAndSettle();

    expect(_plane, findsNothing);
    expect(dialog.result, completion(isTrue));
  });

  for (final (answer, respond)
      in <(String, Future<void> Function(WidgetTester))>[
        ('основная кнопка', (tester) => tester.tap(find.text(_keepLabel))),
        ('касание затемнения', (tester) => tester.tapAt(const Offset(10, 10))),
        ('системное «назад»', (tester) => tester.binding.handlePopRoute()),
      ]) {
    testWidgets('в диалоге отмены изменений $answer закрывает диалог и '
        'сохраняет работу', (tester) async {
      final dialog = _Dialog(show: _showDiscard);
      _useScreen(tester);
      await tester.pumpWidget(dialog.app());
      await dialog.open(tester, overSheet: true);

      await respond(tester);
      await tester.pumpAndSettle();

      expect(_plane, findsNothing);
      expect(find.text(_sheetText), findsOneWidget);
      expect(dialog.result, completion(isFalse));
    });
  }

  testWidgets('диалог отмены изменений объявляет себя маршрутом с названием '
      'по заголовку, а затемнение называет сохранение работы', (tester) async {
    final semantics = tester.ensureSemantics();
    final dialog = _Dialog(show: _showDiscard);
    _useScreen(tester);
    await tester.pumpWidget(dialog.app());
    await dialog.open(tester);

    expect(
      find.semantics.byPredicate(
        (node) =>
            node.label == _discardTitle &&
            node.flagsCollection.scopesRoute &&
            node.flagsCollection.namesRoute,
      ),
      findsOne,
    );
    expect(
      find.semantics.byPredicate(
        (node) =>
            node.label == _keepLabel &&
            node.getSemanticsData().hasAction(SemanticsAction.dismiss),
      ),
      findsOne,
    );
    for (final label in [_discardLabel, _keepLabel]) {
      expect(
        tester.getSemantics(find.text(label)),
        isSemantics(label: label, isButton: true, hasTapAction: true),
      );
    }
    semantics.dispose();
  });

  testWidgets('с крупным шрифтом длинные подписи диалога отмены изменений '
      'переносятся и остаются в плоскости', (tester) async {
    const discardLabel = 'Отменить все изменения заметки';
    const keepLabel = 'Продолжить редактирование заметки';
    final dialog = _Dialog(
      show: (context) => _showDiscardWith(
        context,
        discardLabel: discardLabel,
        keepLabel: keepLabel,
      ),
    );
    _useScreen(tester, textScale: 2);
    await tester.pumpWidget(dialog.app());
    await dialog.open(tester);

    expect(tester.takeException(), isNull);
    final plane = tester.getRect(_plane);
    for (final label in [discardLabel, keepLabel]) {
      final pill = tester.getRect(_pillOf(label));
      final text = tester.getRect(find.text(label));
      // Строка подписи 20 при двукратном шрифте занимает 40.
      expect(text.height, greaterThanOrEqualTo(2 * 40), reason: label);
      expect(pill.top, lessThan(text.top), reason: label);
      expect(pill.bottom, greaterThan(text.bottom), reason: label);
      expect(plane.left, lessThanOrEqualTo(pill.left), reason: label);
      expect(plane.right, greaterThanOrEqualTo(pill.right), reason: label);
    }

    await tester.tap(find.text(keepLabel));
    await tester.pumpAndSettle();
    expect(dialog.result, completion(isFalse));
  });
}

const _title = 'Удалить тег?';
const _sheetText = 'Содержимое листа';
const _preservingTitle = 'Восстановить связь?';
const _warning = 'Вид «можно» из формы не сохранится.';
const _discardTitle = 'Отменить изменения?';
const _discardText = 'Изменения заметки не сохранятся.';
const _discardLabel = 'Выйти';
const _keepLabel = 'Остаться';
const _screen = Size(390, 844);

/// Страница, с которой [show] открывает диалог, и результат его показа.
final class _Dialog {
  _Dialog({this.show = _showConfirm});

  final Future<bool> Function(BuildContext context) show;
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
    result = show(_openerContext);
    await tester.pumpAndSettle();
  }
}

Future<bool> _showConfirm(BuildContext context) => showConfirmDialog(
  context: context,
  title: _title,
  text: const ConfirmDialogText(
    before: 'Тег «',
    name: 'спорт',
    after: '» будет удалён.',
  ),
  cancelLabel: 'Отмена',
  actionLabel: 'Удалить',
);

Future<bool> _showPreserving(
  BuildContext context, {
  String? warning = _warning,
}) => showPreservingConfirmDialog(
  context: context,
  title: _preservingTitle,
  text: const ConfirmDialogText(
    before: 'Связь «',
    name: 'Гулять',
    after: '» снова станет активной.',
  ),
  warning: warning,
  cancelLabel: 'Отмена',
  actionLabel: 'Вернуть',
);

Future<bool> _showDiscard(BuildContext context) => _showDiscardWith(
  context,
  discardLabel: _discardLabel,
  keepLabel: _keepLabel,
);

Future<bool> _showDiscardWith(
  BuildContext context, {
  required String discardLabel,
  required String keepLabel,
}) => showDiscardDialog(
  context: context,
  title: _discardTitle,
  text: _discardText,
  discardLabel: discardLabel,
  keepLabel: keepLabel,
);

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

final _preservingParagraph = find.byWidgetPredicate(
  (widget) =>
      widget is RichText && widget.text.toPlainText().contains('Гулять'),
);

final _discardParagraph = find.byWidgetPredicate(
  (widget) => widget is RichText && widget.text.toPlainText() == _discardText,
);

Finder _pillOf(String label) => find.descendant(
  of: find.widgetWithText(Button, label),
  matching: find.byType(Material),
);

Color? _pillColorOf(WidgetTester tester, String label) =>
    tester.widget<Material>(_pillOf(label)).color;

Color? _labelColorOf(WidgetTester tester, String label) => tester
    .renderObject<RenderParagraph>(
      find.descendant(of: find.text(label), matching: find.byType(RichText)),
    )
    .text
    .style!
    .color;

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
