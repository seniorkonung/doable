import 'package:flutter/material.dart';

import '../doable_colors.dart';
import '../doable_metrics.dart';
import '../doable_type.dart';

/// Заголовок дня с готовыми текстами; отсутствие [todayLabel] скрывает отметку.
///
/// [trailing] стоит в конце первой строки дня: по центру её высоты 24, если
/// ниже неё, и не шире половины заголовка. Дню недели остаётся другое место,
/// поэтому текст переносится, а не уходит под содержимое слота.
final class DayHeading extends StatelessWidget {
  const DayHeading({
    super.key,
    required this.weekday,
    required this.date,
    this.todayLabel,
    this.trailing,
  });

  static const double _weekdayLineHeight = 24;

  final String weekday;
  final String date;
  final String? todayLabel;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<DoableColors>()!;
    final weekdayLine = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: _weekdayLineHeight),
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
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Слот в строке получил бы неограниченную ширину:
        // https://api.flutter.dev/flutter/rendering/RenderFlex-class.html
        LayoutBuilder(
          builder: (context, constraints) => Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: DoableMetrics.space2,
            children: [
              Expanded(child: weekdayLine),
              if (trailing case final trailing?)
                ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: _weekdayLineHeight,
                    maxWidth: constraints.maxWidth / 2,
                  ),
                  child: Center(
                    widthFactor: 1,
                    heightFactor: 1,
                    child: trailing,
                  ),
                ),
            ],
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
