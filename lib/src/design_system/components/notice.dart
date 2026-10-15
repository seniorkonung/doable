import 'package:flutter/material.dart';

import '../doable_colors.dart';
import '../doable_metrics.dart';
import '../doable_type.dart';

/// Пассивное сообщение об отказе с объявлением для экранного диктора.
final class Notice extends StatelessWidget {
  const Notice({super.key, required this.message});

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
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(Icons.error_outline, size: 20, color: colors.danger),
            ),
            const SizedBox(width: DoableMetrics.space3),
            Expanded(
              // Объявление при появлении сообщения не требует перевода фокуса:
              // https://api.flutter.dev/flutter/semantics/SemanticsProperties/liveRegion.html
              child: Semantics(
                liveRegion: true,
                child: Text(
                  message,
                  style: DoableType.body.copyWith(color: colors.ink),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
