import 'package:flutter/material.dart';

import '../doable_colors.dart';
import '../doable_metrics.dart';
import '../doable_type.dart';

/// Пустое состояние списка: заголовок о том, что пусто, и текст о том, что
/// здесь появится или что изменить.
///
/// Блок центрируется в высоте, которую даёт родитель, и оставляет под собой
/// свободные 40. В прокручиваемом теле его кладут в
/// `SliverFillRemaining(hasScrollBody: false)`: тогда в низком месте блок
/// начинается сверху и прокручивается.
final class EmptyState extends StatelessWidget {
  static const double _textMaxWidth = 260;

  const EmptyState({required this.title, required this.text, super.key});

  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<DoableColors>()!;
    return Padding(
      padding: const EdgeInsets.only(bottom: DoableMetrics.space10),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
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
          ],
        ),
      ),
    );
  }
}
