import 'package:flutter/material.dart';

import '../doable_colors.dart';
import '../doable_metrics.dart';
import '../doable_type.dart';

/// Заголовок дня с готовыми текстами; отсутствие [todayLabel] скрывает отметку.
final class DayHeading extends StatelessWidget {
  const DayHeading({
    super.key,
    required this.weekday,
    required this.date,
    this.todayLabel,
  });

  final String weekday;
  final String date;
  final String? todayLabel;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<DoableColors>()!;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 24),
          child: Padding(
            padding: const EdgeInsets.only(top: 2),
            // Встроенная отметка выравнивается по тексту и переносится с ним:
            // https://api.flutter.dev/flutter/widgets/WidgetSpan-class.html
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: weekday),
                  if (todayLabel case final label?)
                    WidgetSpan(
                      alignment: PlaceholderAlignment.baseline,
                      baseline: TextBaseline.alphabetic,
                      style: DoableType.caption,
                      child: Padding(
                        padding: const EdgeInsetsDirectional.only(
                          start: DoableMetrics.space2,
                        ),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: colors.accentSoft,
                            borderRadius: BorderRadius.circular(
                              DoableMetrics.radiusXs,
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 1,
                            ),
                            child: Text(
                              label,
                              // WidgetSpan уже масштабирует отметку целиком:
                              // https://api.flutter.dev/flutter/widgets/WidgetSpan/extractFromInlineSpan.html
                              textScaler: TextScaler.noScaling,
                              style: DoableType.caption.copyWith(
                                color: colors.accent,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              style: DoableType.body.copyWith(
                color: colors.muted,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
        const SizedBox(height: 2),
        Semantics(
          header: true,
          child: Text(
            date,
            style: DoableType.display.copyWith(color: colors.ink),
          ),
        ),
      ],
    );
  }
}
