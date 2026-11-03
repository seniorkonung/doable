import 'package:flutter/material.dart';

import '../doable_colors.dart';
import '../doable_metrics.dart';

/// Нижняя часть экрана, закреплённая как `NavBar`: плоскость `raised` с линией
/// `hairline` сверху, высота `nav-height` с системным отступом и основная
/// кнопка [child] на всю ширину. С крупным шрифтом растёт вместе с кнопкой.
final class DockedFooter extends StatelessWidget {
  const DockedFooter({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<DoableColors>()!;
    return Material(
      color: colors.raised,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: colors.hairline)),
        ),
        child: SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: DoableMetrics.navHeight,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: DoableMetrics.space5,
              ),
              child: Center(heightFactor: 1, child: child),
            ),
          ),
        ),
      ),
    );
  }
}
