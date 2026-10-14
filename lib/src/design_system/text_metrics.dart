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
    var height = 0.0;
    for (final text in texts) {
      painter
        ..text = TextSpan(text: text, style: effectiveStyle)
        ..layout(maxWidth: math.max(0, maxWidth));
      height = math.max(height, painter.height);
    }
    return height;
  } finally {
    painter.dispose();
  }
}
