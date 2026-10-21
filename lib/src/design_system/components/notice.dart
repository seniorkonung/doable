import 'package:flutter/material.dart';

import '../doable_colors.dart';
import '../doable_icon.dart';
import '../doable_metrics.dart';
import '../doable_shadows.dart';
import '../doable_type.dart';

/// Карточка отказа. Строковое сообщение объявляется экранному диктору,
/// а в [Notice.content] объявлением владеет переданный виджет сообщения.
final class Notice extends StatelessWidget {
  const Notice({super.key, required String message})
    : _text = message,
      _content = null,
      action = null;

  /// Сообщение со значком предупреждения и необязательным действием.
  /// Компонент задаёт стиль текста, но не объявляет сообщение сам.
  const Notice.content({super.key, required Widget message, this.action})
    : _content = message,
      _text = null;

  final String? _text;
  final Widget? _content;

  /// Действие исправления; без него сообщение только объясняет отказ.
  final ({String label, VoidCallback onPressed})? action;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<DoableColors>()!;
    final messageStyle = DoableType.body.copyWith(color: colors.ink);
    final content = _content;
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
              child: content == null
                  ? Icon(Icons.error_outline, size: 20, color: colors.danger)
                  : DoableIcon(
                      DoableIconData.warning,
                      size: 20,
                      color: colors.accent,
                    ),
            ),
            const SizedBox(width: DoableMetrics.space3),
            Expanded(
              child: content == null
                  // Конструкторы задают ровно один вид сообщения: текст
                  // с собственным объявлением либо готовый виджет.
                  ? Semantics(
                      liveRegion: true,
                      child: Text(_text!, style: messageStyle),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        DefaultTextStyle.merge(
                          style: messageStyle,
                          child: content,
                        ),
                        if (action != null)
                          _NoticeAction(
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
final class _NoticeAction extends StatelessWidget {
  const _NoticeAction({required this.label, required this.onPressed});

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
