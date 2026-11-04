import 'package:flutter/material.dart';

import '../doable_colors.dart';
import '../doable_icon.dart';
import '../doable_metrics.dart';
import '../doable_shadows.dart';

/// Круглая плавающая кнопка, возвращающая длинный список к началу.
///
/// Потребитель решает, когда её показывать и где ставить, задаёт доступное
/// название [label] и команду [onPressed]. Плавное или мгновенное движение
/// списка тоже остаётся за потребителем. Над нижней панелью её ставит
/// [ScrollTopButtonLocation].
///
/// Круг 44 цвета `raised` с обводкой `hairline` и тенью `shadow-float`,
/// внутри стрелка к линии размером 20 цвета `ink`.
final class ScrollTopButton extends StatelessWidget {
  const ScrollTopButton({
    required this.label,
    required this.onPressed,
    super.key,
  });

  /// Доступное название кнопки.
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<DoableColors>()!;
    final shadows = theme.extension<DoableShadows>()!;
    final shape = CircleBorder(side: BorderSide(color: colors.hairline));

    // Название, роль и команда нажатия принадлежат одной кнопке:
    // https://api.flutter.dev/flutter/widgets/MergeSemantics-class.html
    return MergeSemantics(
      child: Semantics(
        button: true,
        label: label,
        child: DecoratedBox(
          decoration: ShapeDecoration(
            color: colors.raised,
            shape: shape,
            shadows: shadows.shadowFloat,
          ),
          child: Material(
            type: MaterialType.transparency,
            shape: shape,
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onPressed,
              customBorder: shape,
              child: ExcludeSemantics(
                child: SizedBox.square(
                  dimension: DoableMetrics.tapMin,
                  child: Center(
                    child: DoableIcon(
                      DoableIconData.toTop,
                      size: 20,
                      color: colors.ink,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Место [ScrollTopButton] в слоте плавающей кнопки `Scaffold`: `space5` от
/// правого края и `space3` над нижней панелью.
///
/// Плавающее сообщение `Scaffold` сам ставит над кнопкой этого слота.
final class ScrollTopButtonLocation extends FloatingActionButtonLocation {
  const ScrollTopButtonLocation();

  @override
  Offset getOffset(ScaffoldPrelayoutGeometry scaffoldGeometry) {
    final size = scaffoldGeometry.floatingActionButtonSize;
    return Offset(
      scaffoldGeometry.scaffoldSize.width -
          scaffoldGeometry.minInsets.right -
          DoableMetrics.space5 -
          size.width,
      scaffoldGeometry.contentBottom - DoableMetrics.space3 - size.height,
    );
  }
}
