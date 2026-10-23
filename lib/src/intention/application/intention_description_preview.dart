import 'package:characters/characters.dart';

/// Начало сохранённого описания намерения для краткого представления.
///
/// Серии пробельных символов свёрнуты в один пробел, края обрезаны,
/// длина ограничена [maxLength] расширенными графемными кластерами.
/// Текст непуст: описание без непробельного символа не сохраняется.
final class IntentionDescriptionPreview {
  factory IntentionDescriptionPreview.fromDescription(String description) {
    final text = description
        .replaceAll(_whitespaceRun, ' ')
        .trim()
        .characters
        .take(maxLength)
        .toString();
    if (text.isEmpty) {
      // Текст описания не попадает в ошибку, как и в остальную диагностику.
      throw ArgumentError(
        'Описание должно содержать непробельный символ.',
        'description',
      );
    }
    return IntentionDescriptionPreview._(text);
  }

  const IntentionDescriptionPreview._(this.text);

  static const int maxLength = 512;

  // Те же символы, что обрезает `String.trim`: Unicode White_Space и U+FEFF.
  // `\s` не подходит: он не включает U+0085.
  static final _whitespaceRun = RegExp(
    '[\t\n\u000B\f\r \u0085\u00A0\u1680\u2000-\u200A'
    '\u2028\u2029\u202F\u205F\u3000\uFEFF]+',
  );

  final String text;
}
