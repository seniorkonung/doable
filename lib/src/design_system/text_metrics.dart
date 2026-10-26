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
  final defaultStyle = DefaultTextStyle.of(context);
  var effectiveStyle = defaultStyle.style.merge(style);
  if (MediaQuery.boldTextOf(context)) {
    effectiveStyle = effectiveStyle.merge(
      const TextStyle(fontWeight: FontWeight.bold),
    );
  }
  final painter = TextPainter(
    textAlign: TextAlign.center,
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    locale: Localizations.maybeLocaleOf(context),
    textHeightBehavior:
        defaultStyle.textHeightBehavior ??
        DefaultTextHeightBehavior.maybeOf(context),
    textWidthBasis: defaultStyle.textWidthBasis,
  );
  try {
    var result = 0.0;
    for (final text in texts) {
      painter
        ..text = TextSpan(text: text, style: effectiveStyle)
        ..layout(maxWidth: maxWidth);
      result = math.max(result, extent(painter));
    }
    return result;
  } finally {
    painter.dispose();
  }
}
