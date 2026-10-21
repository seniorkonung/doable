import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Показанный текст без декоративных виджетов внутри строки.
String textIgnoringInlineWidgets(Text text) =>
    text.data ??
    text.textSpan!.toPlainText(
      includeSemanticsLabels: false,
      includePlaceholders: false,
    );

Finder findTextIgnoringInlineWidgets(String text) => find.byWidgetPredicate(
  (widget) => widget is Text && textIgnoringInlineWidgets(widget) == text,
  description: 'текст «$text» без встроенных виджетов',
);
