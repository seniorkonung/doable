import 'package:flutter/material.dart';

import '../doable_colors.dart';
import '../doable_icon.dart';
import '../doable_metrics.dart';
import '../doable_type.dart';
import 'button.dart';

/// Пустое состояние списка: заголовок о том, что пусто, и текст о том, что
/// здесь появится или что изменить. Над заголовком может стоять круг
/// с иконкой, а под текстом — одна тихая кнопка.
///
/// Блок центрируется в высоте, которую даёт родитель, и оставляет под собой
/// свободные 40. В прокручиваемом теле его кладут в
/// `SliverFillRemaining(hasScrollBody: false)`: тогда в низком месте блок
/// начинается сверху и прокручивается.
final class EmptyState extends StatelessWidget {
  static const double _textMaxWidth = 260;

  const EmptyState({
    required this.title,
    required this.text,
    this.icon,
    this.action,
    super.key,
  });

  final String title;
  final String text;
  final DoableIconData? icon;

  /// Действие, которое меняет то, из-за чего пусто, например «Сбросить
  /// фильтры».
  final ({String label, VoidCallback onPressed})? action;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<DoableColors>()!;
    return Padding(
      padding: const EdgeInsets.only(bottom: DoableMetrics.space10),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon case final icon?) ...[
              SizedBox.square(
                dimension: 52,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.fill,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: DoableIcon(
                      icon,
                      size: DoableMetrics.iconSize,
                      color: colors.muted,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
            ],
            Semantics(
              container: true,
              header: true,
              child: Text(
                title,
                textAlign: TextAlign.center,
                style: DoableType.title.copyWith(color: colors.ink),
              ),
            ),
            const SizedBox(height: 6),
            // В отличие от ConstrainedBox, предел ширины учитывается и в
            // собственной высоте, по которой SliverFillRemaining выбирает
            // высоту блока в низком месте:
            // https://api.flutter.dev/flutter/widgets/ConstraintsTransformBox-class.html
            ConstraintsTransformBox(
              constraintsTransform: (constraints) => constraints.enforce(
                const BoxConstraints(maxWidth: _textMaxWidth),
              ),
              child: Text(
                text,
                textAlign: TextAlign.center,
                style: DoableType.body.copyWith(color: colors.muted),
              ),
            ),
            if (action case (:final label, :final onPressed)) ...[
              // Область нажатия кнопки на 4 выше её плашки, поэтому плашка
              // стоит в 16 под текстом.
              const SizedBox(height: 12),
              Button.quiet(label: label, onPressed: onPressed),
            ],
          ],
        ),
      ),
    );
  }
}
