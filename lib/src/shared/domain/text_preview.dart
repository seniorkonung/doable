import 'package:characters/characters.dart';

/// Начало текста для краткого представления.
///
/// Серии пробельных символов свёрнуты в один пробел, края обрезаны,
/// длина ограничена [maxLength] расширенными графемными кластерами.
/// Текст непуст: строка без непробельного символа начала не имеет.
final class TextPreview {
  factory TextPreview.fromText(String text) {
    final preview = text
        .replaceAll(_whitespaceRun, ' ')
        .trim()
        .characters
        .take(maxLength)
        .toString();
    if (preview.isEmpty) {
      // Исходный текст не попадает в ошибку, как и в остальную диагностику.
      throw ArgumentError(
        'Текст должен содержать непробельный символ.',
        'text',
      );
    }
    return TextPreview._(preview);
  }

  const TextPreview._(this.text);

  static const int maxLength = 512;

  // Те же символы, что обрезает `String.trim`: Unicode White_Space и U+FEFF.
  // `\s` не подходит: он не включает U+0085.
  static final _whitespaceRun = RegExp(
    '[\t\n\u000B\f\r \u0085   - '
    '    　﻿]+',
  );

  final String text;
}
