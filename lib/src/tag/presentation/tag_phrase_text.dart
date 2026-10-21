import 'package:flutter/widgets.dart';

import '../../design_system/components/tag_dot.dart';
import '../domain/tag_color.dart';
import 'tag_color_presentation.dart';

/// Локализованная фраза с точками перед названиями тегов.
///
/// [phrase] вставляет свой аргумент ровно один раз. Место вставки определяется
/// до подстановки пользовательских названий, поэтому их текст не разбирается.
/// Экранный диктор получает ту же фразу без декоративных точек.
Text tagPhraseText({
  required String Function(String) phrase,
  required List<({String name, TagColor? color})> tags,
  required TagDotSize dotSize,
}) {
  const placeholder = '\uFFFC';
  final [prefix, suffix] = phrase(placeholder).split(placeholder);
  return Text.rich(
    TextSpan(
      children: [
        TextSpan(text: prefix),
        for (final (index, tag) in tags.indexed) ...[
          if (index > 0) const TextSpan(text: ', '),
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Padding(
              padding: const EdgeInsetsDirectional.only(end: 4),
              child: TagDot(
                color: tagColorPresentation(tag.color),
                size: dotSize,
              ),
            ),
          ),
          TextSpan(text: tag.name),
        ],
        TextSpan(text: suffix),
      ],
    ),
    semanticsLabel: phrase(tags.map((tag) => tag.name).join(', ')),
  );
}
