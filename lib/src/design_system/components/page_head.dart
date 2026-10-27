import 'package:flutter/material.dart';

import '../doable_colors.dart';
import '../doable_type.dart';

/// Полное название страницы. Боковые поля задаёт сама страница.
final class PageHead extends StatelessWidget {
  const PageHead({required this.name, super.key});

  final String name;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<DoableColors>()!;
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 6),
      // Панель над шапкой содержит первый заголовок экрана:
      // https://api.flutter.dev/flutter/semantics/SemanticsProperties/headingLevel.html
      child: Semantics(
        headingLevel: 2,
        child: Text(
          name,
          softWrap: true,
          style: DoableType.pageTitle.copyWith(color: colors.ink),
        ),
      ),
    );
  }
}
