import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Наибольшая высота, которую займёт виджет `Text` с одним из [texts] и стилем
/// [style] в [context] при ширине не больше [maxWidth].
///
/// Текст измеряется по тем же правилам, что применяет `Text`: стиль по
/// умолчанию, системный масштаб и жирность текста, локаль и направление. Если
/// текст не помещается в ширину, он переносится, и в высоту входят все строки.
/// Отрицательная ширина считается нулевой.
///
/// Нужна, когда высоту ячейки задают заранее, а не по её содержимому.
double tallestTextHeight(
  BuildContext context, {
  required Iterable<String> texts,
  required TextStyle? style,
  required double maxWidth,
}) => _measure(
  context,
  texts: texts,
  style: style,
  maxWidth: math.max(0, maxWidth),
  extent: (painter) => painter.height,
);

/// Наибольшая ширина, которую займёт виджет `Text` с одним из [texts] и стилем
/// [style] в [context], когда ширина не ограничена и текст стоит в одну
/// строку.
///
/// Текст измеряется по тем же правилам, что и в [tallestTextHeight]. Ширина
/// округляется вверх до целого: в ширине, равной результату, текст не
/// переносится из-за погрешности дробных метрик.
///
/// Нужна, когда ширину плоскости задаёт самый длинный текст до её раскладки.
double widestTextWidth(
  BuildContext context, {
  required Iterable<String> texts,
  required TextStyle? style,
}) => _measure(
  context,
  texts: texts,
  style: style,
  maxWidth: double.infinity,
  extent: (painter) => painter.maxIntrinsicWidth.ceilToDouble(),
);

double _measure(
  BuildContext context, {
  required Iterable<String> texts,
  required TextStyle? style,
  required double maxWidth,
  required double Function(TextPainter painter) extent,
}) {
  final rules = TextLayoutRules.of(context, style: style);
  final painter = rules._painter();
  try {
    var result = 0.0;
    for (final text in texts) {
      rules._layout(painter, text, maxWidth: maxWidth);
      result = math.max(result, extent(painter));
    }
    return result;
  } finally {
    painter.dispose();
  }
}

/// Правила, по которым виджет `Text` со стилем раскладывает текст в
/// контексте: стиль по умолчанию, системный масштаб и жирность текста, локаль
/// и направление.
///
/// Правила снимаются с контекста при сборке, поэтому по ним можно измерять
/// текст и при раскладке, когда ширина уже известна.
final class TextLayoutRules {
  factory TextLayoutRules.of(
    BuildContext context, {
    required TextStyle? style,
  }) {
    final defaultStyle = DefaultTextStyle.of(context);
    var effectiveStyle = defaultStyle.style.merge(style);
    if (MediaQuery.boldTextOf(context)) {
      effectiveStyle = effectiveStyle.merge(
        const TextStyle(fontWeight: FontWeight.bold),
      );
    }
    return TextLayoutRules._(
      effectiveStyle,
      Directionality.of(context),
      MediaQuery.textScalerOf(context),
      Localizations.maybeLocaleOf(context),
      defaultStyle.textHeightBehavior ??
          DefaultTextHeightBehavior.maybeOf(context),
      defaultStyle.textWidthBasis,
    );
  }

  const TextLayoutRules._(
    this._style,
    this._textDirection,
    this._textScaler,
    this._locale,
    this._textHeightBehavior,
    this._textWidthBasis,
  );

  /// На сколько ширина становится уже самой длинной строки, чтобы та
  /// перенеслась раньше.
  static const double _narrowingStep = 0.5;

  final TextStyle _style;
  final TextDirection _textDirection;
  final TextScaler _textScaler;
  final Locale? _locale;
  final TextHeightBehavior? _textHeightBehavior;
  final TextWidthBasis _textWidthBasis;

  /// Ширина не больше [maxWidth], в которой последняя строка [text] не
  /// состоит из одного слова.
  ///
  /// Если в [maxWidth] текст стоит в одну строку или в его последней строке
  /// больше одного слова, возвращает [maxWidth]. Иначе возвращает наибольшую
  /// ширину, в которой в последней строке не меньше двух слов, а строк не
  /// больше, чем в [maxWidth], и слова не разрываются. Если такой ширины нет,
  /// возвращает [maxWidth], и текст переносится как обычно.
  double prettyWidth(String text, {required double maxWidth}) {
    final painter = _painter();
    try {
      _layout(painter, text, maxWidth: maxWidth);
      final lineCount = painter.computeLineMetrics().length;
      // Уже самого длинного слова текст переносится внутри слов.
      final longestWord = painter.minIntrinsicWidth;
      // Пока ширина не уже самой длинной строки, переносы не меняются,
      // поэтому проверяются только ширины, на которых они меняются.
      var width = maxWidth;
      while (lineCount > 1) {
        final lines = painter.computeLineMetrics();
        if (lines.length > lineCount) {
          break;
        }
        final lastLine = painter.getLineBoundary(
          TextPosition(offset: text.length, affinity: TextAffinity.upstream),
        );
        if (lastLine.textInside(text).trim().contains(_space)) {
          return width;
        }
        final longest = lines.map((line) => line.width).reduce(math.max);
        width = math.min(width, longest) - _narrowingStep;
        if (width < longestWord) {
          break;
        }
        _layout(painter, text, maxWidth: width);
      }
      return maxWidth;
    } finally {
      painter.dispose();
    }
  }

  static final _space = RegExp(r'\s');

  TextPainter _painter() => TextPainter(
    textAlign: TextAlign.center,
    textDirection: _textDirection,
    textScaler: _textScaler,
    locale: _locale,
    textHeightBehavior: _textHeightBehavior,
    textWidthBasis: _textWidthBasis,
  );

  void _layout(TextPainter painter, String text, {required double maxWidth}) {
    painter
      ..text = TextSpan(text: text, style: _style)
      ..layout(maxWidth: maxWidth);
  }
}
