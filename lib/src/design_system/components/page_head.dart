import 'package:flutter/material.dart';

import '../doable_colors.dart';
import '../doable_type.dart';

/// Полное название страницы. Боковые поля задаёт сама страница.
///
/// Название — кнопка изменения с доступным названием [editLabel].
/// Пока [onEdit] не задан, кнопка выключена.
final class PageHead extends StatelessWidget {
  const PageHead({
    required this.name,
    required this.editLabel,
    required this.onEdit,
    super.key,
  });

  final String name;
  final String editLabel;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<DoableColors>()!;
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 6),
      child: MergeSemantics(
        // Панель над шапкой содержит первый заголовок экрана:
        // https://api.flutter.dev/flutter/semantics/SemanticsProperties/headingLevel.html
        child: Semantics(
          button: true,
          enabled: onEdit != null,
          headingLevel: 2,
          label: editLabel,
          child: InkWell(
            onTap: onEdit,
            child: ExcludeSemantics(
              child: Text(
                name,
                softWrap: true,
                style: DoableType.pageTitle.copyWith(color: colors.ink),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
