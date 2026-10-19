import 'package:flutter/material.dart';

import '../doable_colors.dart';
import '../doable_icon.dart';
import '../doable_metrics.dart';
import '../doable_shadows.dart';
import '../doable_type.dart';

/// Сообщение об отказе со значком предупреждения и, если отказ можно
/// исправить, действием исправления под текстом.
///
/// Текст сообщения показывает потребитель в [message] стилем, который задаёт
/// компонент. Объявление сообщения экранным диктором тоже остаётся за
/// потребителем: так текст может показать виджет, который подтверждает его
/// предъявление.
final class FailureNotice extends StatelessWidget {
  const FailureNotice({required this.message, this.action, super.key});

  final Widget message;

  /// Действие исправления; без него сообщение только объясняет отказ.
  final ({String label, VoidCallback onPressed})? action;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<DoableColors>()!;
    final action = this.action;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.fill,
        borderRadius: BorderRadius.circular(DoableMetrics.radiusLg),
      ),
      child: Padding(
        // Область нажатия действия выше его плашки, поэтому снизу под ним
        // отступ меньше, как в макете.
        padding: EdgeInsets.fromLTRB(
          DoableMetrics.space4,
          14,
          DoableMetrics.space4,
          action == null ? 14 : DoableMetrics.space2,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: DoableIcon(
                DoableIconData.warning,
                size: 20,
                color: colors.accent,
              ),
            ),
            const SizedBox(width: DoableMetrics.space3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DefaultTextStyle.merge(
                    style: DoableType.body.copyWith(color: colors.ink),
                    child: message,
                  ),
                  if (action != null)
                    _FailureNoticeAction(
                      label: action.label,
                      onPressed: action.onPressed,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Действие сообщения: плашка высотой от 32 в области нажатия высотой от
/// 44. Обе растут вместе с крупным шрифтом.
final class _FailureNoticeAction extends StatelessWidget {
  const _FailureNoticeAction({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<DoableColors>()!;
    final shadows = theme.extension<DoableShadows>()!;
    const radius = BorderRadius.all(Radius.circular(DoableMetrics.radiusLg));
    return MergeSemantics(
      child: Semantics(
        button: true,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onPressed,
            borderRadius: radius,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: DoableMetrics.tapMin,
              ),
              child: Align(
                widthFactor: 1,
                // Ink рисует плашку на Material, под откликом всей кнопки:
                // https://api.flutter.dev/flutter/material/InkWell-class.html
                child: Ink(
                  decoration: BoxDecoration(
                    color: colors.raised,
                    borderRadius: radius,
                    boxShadow: shadows.sm,
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 32),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Align(
                        widthFactor: 1,
                        child: Text(
                          label,
                          style: DoableType.label.copyWith(color: colors.ink),
                        ),
                      ),
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
