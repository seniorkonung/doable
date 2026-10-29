import 'package:flutter/material.dart' hide Badge;

import '../doable_colors.dart';
import '../doable_metrics.dart';
import '../doable_type.dart';
import 'badge.dart';
import 'button.dart';

/// Полное название страницы. Боковые поля задаёт сама страница.
///
/// Название — кнопка изменения с доступным названием [editLabel].
/// Пока [onEdit] не задан, кнопка выключена.
final class PageHead extends StatelessWidget {
  const PageHead({
    required this.name,
    required this.editLabel,
    required this.onEdit,
    this.muted = false,
    this.badge,
    this.note,
    this.button,
    super.key,
  });

  final String name;
  final String editLabel;
  final VoidCallback? onEdit;

  /// Название цветом `muted` вместо `ink`, как у архивированного намерения.
  final bool muted;

  /// Метка на строке названия в 8 после него, а если название заполняет
  /// строку, — на своей строке в 6 ниже.
  final Badge? badge;

  /// Строка пояснения стилем `hint` в 6 под названием.
  final String? note;

  /// Единственная кнопка шапки на всю её ширину в 10 под текстом.
  final Button? button;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<DoableColors>()!;
    final title = MergeSemantics(
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
              style: DoableType.pageTitle.copyWith(
                color: muted ? colors.muted : colors.ink,
              ),
            ),
          ),
        ),
      ),
    );
    final badge = this.badge;
    final note = this.note;
    final button = this.button;
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (badge == null)
            title
          else
            Wrap(
              spacing: DoableMetrics.space2,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [title, badge],
            ),
          if (note != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                note,
                style: DoableType.hint.copyWith(color: colors.muted),
              ),
            ),
          if (button != null)
            Padding(padding: const EdgeInsets.only(top: 10), child: button),
        ],
      ),
    );
  }
}
