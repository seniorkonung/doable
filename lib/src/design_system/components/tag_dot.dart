import 'package:flutter/material.dart';

import '../doable_colors.dart';

/// Цвета тега в порядке палитры; отсутствие варианта означает «Без цвета».
enum DoableTagColor {
  brown(DoableColorToken.tagBrown),
  orange(DoableColorToken.tagOrange),
  olive(DoableColorToken.tagOlive),
  green(DoableColorToken.tagGreen),
  teal(DoableColorToken.tagTeal),
  blue(DoableColorToken.tagBlue),
  violet(DoableColorToken.tagViolet),
  purple(DoableColorToken.tagPurple),
  pink(DoableColorToken.tagPink);

  const DoableTagColor(this.token);

  /// Заливка варианта; общая для точки и выбора цвета.
  final DoableColorToken token;
}

/// Размеры точки по месту показа тега.
enum TagDotSize {
  /// Теги в кратких строках.
  small(7),

  /// Теги формы.
  medium(8),

  /// Строки каталога и поле названия тега.
  large(10);

  const TagDotSize(this.diameter);

  final double diameter;
}

/// Цвет тега перед его названием: заполненная точка или кольцо «Без цвета»,
/// отличимые формой, а не только цветом. Узла экранного диктора у точки нет:
/// тег называет его название.
final class TagDot extends StatelessWidget {
  const TagDot({required this.color, required this.size, super.key});

  final DoableTagColor? color;
  final TagDotSize size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors =
        theme.extension<DoableColors>() ??
        switch (theme.brightness) {
          Brightness.light => DoableColors.light,
          Brightness.dark => DoableColors.dark,
        };

    return SizedBox.square(
      dimension: size.diameter,
      child: DecoratedBox(
        decoration: switch (color) {
          final color? => BoxDecoration(
            shape: BoxShape.circle,
            color: colors[color.token],
          ),
          null => BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: colors.grip, width: 1.5),
          ),
        },
      ),
    );
  }
}
