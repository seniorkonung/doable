import 'package:flutter/material.dart';

import '../doable_colors.dart';
import '../doable_metrics.dart';
import '../doable_type.dart';

/// Кнопка-пилюля, подпись которой называет действие нажатия.
final class Button extends StatelessWidget {
  /// Основное действие листа или экрана: плашка `ink` с текстом `bg`
  /// на всю ширину контейнера. Одна на плоскость.
  const Button.primary({
    required this.label,
    required this.onPressed,
    super.key,
  });

  final String label;

  /// Без обработчика кнопка выключена: остаётся на своём месте плашкой
  /// `fill` с текстом `grip` и объявляется недоступной.
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<DoableColors>()!;
    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: colors.ink,
        foregroundColor: colors.bg,
        disabledBackgroundColor: colors.fill,
        disabledForegroundColor: colors.grip,
        // Строка подписи 20 и отступы по 10 дают высоту control-height,
        // а с крупным шрифтом плашка растёт вместе с текстом.
        minimumSize: const Size.fromHeight(DoableMetrics.controlHeight),
        padding: const EdgeInsets.symmetric(
          horizontal: DoableMetrics.space4,
          vertical: 10,
        ),
        shape: const StadiumBorder(),
        textStyle: DoableType.section,
        // Область нажатия выше плашки, как требует tap-min:
        // https://api.flutter.dev/flutter/material/MaterialTapTargetSize.html
        tapTargetSize: MaterialTapTargetSize.padded,
      ),
      child: Text(label, textAlign: TextAlign.center),
    );
  }
}
