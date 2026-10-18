import 'package:flutter/material.dart';

import '../doable_colors.dart';
import '../doable_icon.dart';
import '../doable_metrics.dart';
import '../doable_type.dart';

/// Постоянное предупреждение со значком внутри содержимого. В отличие от
/// сообщения об отказе `Notice` оно не объявляется экранным диктором при
/// появлении: диктор читает его вместе с остальным содержимым.
final class Caution extends StatelessWidget {
  const Caution({required this.icon, required this.message, super.key});

  final DoableIconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<DoableColors>()!;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.fill,
        borderRadius: BorderRadius.circular(DoableMetrics.radiusLg),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: DoableMetrics.space4,
          vertical: 14,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DoableIcon(icon, size: 20, color: colors.muted),
            const SizedBox(width: DoableMetrics.space3),
            Expanded(
              child: Text(
                message,
                style: DoableType.body.copyWith(color: colors.ink),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
