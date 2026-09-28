import 'dart:convert';

import 'package:flutter/material.dart';

/// Сохраняет исходный ввод, выделение и область набора без исправлений.
/// Только при отрисовке обозначает недопустимые символы знаком �, поскольку
/// движок Flutter не может строить абзац с непарными UTF-16 surrogate.
final class TagCatalogSearchController extends TextEditingController {
  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final displayed = _displayText(text);
    if (!withComposing || !value.isComposingRangeValid) {
      return TextSpan(style: style, text: displayed);
    }

    final composing = value.composing;
    return TextSpan(
      style: style,
      children: [
        TextSpan(text: _displayText(composing.textBefore(displayed))),
        TextSpan(
          style: const TextStyle(decoration: TextDecoration.underline),
          text: _displayText(composing.textInside(displayed)),
        ),
        TextSpan(text: _displayText(composing.textAfter(displayed))),
      ],
    );
  }

  // Каждый маркер занимает одну кодовую единицу, сохраняя позиции курсора.
  // Этот текст используется только для рисования, а фильтр проверяет ввод.
  String _displayText(String input) =>
      utf8.decode(utf8.encode(input)).replaceAll('\u0000', '\uFFFD');
}
