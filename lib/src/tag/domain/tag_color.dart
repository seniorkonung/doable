/// Цвет тега из палитры дизайн-системы. Отсутствие цвета — `null` в
/// `Tag.color`, а не отдельное значение.
enum TagColor {
  brown('brown'),
  orange('orange'),
  olive('olive'),
  green('green'),
  teal('teal'),
  blue('blue'),
  violet('violet'),
  purple('purple'),
  pink('pink');

  const TagColor(this.code);

  /// Устойчивый код цвета в сохранённых данных. Не зависит от порядка
  /// значений, темы и языка интерфейса.
  final String code;

  /// Неизвестный код — недопустимое значение, а не отсутствие цвета.
  static TagColorDecoding decode(String code) {
    for (final color in values) {
      if (color.code == code) return TagColorDecodingSuccess(color);
    }
    return const UnknownTagColorDecoding();
  }
}

sealed class TagColorDecoding {
  const TagColorDecoding();
}

final class TagColorDecodingSuccess extends TagColorDecoding {
  const TagColorDecodingSuccess(this.color);

  final TagColor color;
}

final class UnknownTagColorDecoding extends TagColorDecoding {
  const UnknownTagColorDecoding();
}
