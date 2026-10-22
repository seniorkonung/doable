import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../doable_colors.dart';
import '../doable_metrics.dart';
import '../doable_shadows.dart';
import '../doable_type.dart';
import 'button.dart';

/// Первый абзац диалога подтверждения: что произойдёт, с выделенным
/// названием [name] того, к чему относится действие, между [before] и
/// [after].
final class ConfirmDialogText {
  const ConfirmDialogText({
    required this.before,
    required this.name,
    this.after = '',
  });

  final String before;
  final String name;
  final String after;
}

/// Показывает над корневым навигатором диалог, который задаёт один вопрос
/// перед необратимым действием, и возвращает, подтверждено ли оно.
///
/// [title] — вопрос, называющий действие и предмет; он же — название
/// маршрута для экранного диктора. [cancelLabel] — подпись quiet-кнопки
/// отмены и доступное название затемнения, [actionLabel] — подпись
/// danger-кнопки, повторяющая глагол вопроса.
///
/// Действие даёт true, а отмена, касание затемнения и системное «назад» —
/// false. Затемнение поверх листов, «назад» и маршрут даёт Material:
/// https://api.flutter.dev/flutter/material/showDialog.html
Future<bool> showConfirmDialog({
  required BuildContext context,
  required String title,
  required ConfirmDialogText text,
  required String cancelLabel,
  required String actionLabel,
}) async {
  final colors = Theme.of(context).extension<DoableColors>()!;
  final confirmed = await showDialog<bool>(
    context: context,
    useRootNavigator: true,
    barrierColor: colors.scrim,
    barrierLabel: cancelLabel,
    builder: (context) => _ConfirmDialog(
      title: title,
      text: text,
      cancelLabel: cancelLabel,
      actionLabel: actionLabel,
    ),
  );
  return confirmed ?? false;
}

final class _ConfirmDialog extends StatelessWidget {
  const _ConfirmDialog({
    required this.title,
    required this.text,
    required this.cancelLabel,
    required this.actionLabel,
  });

  /// Область нажатия кнопок Material выше строки действий макета в 44,
  /// поэтому поля вокруг строки меньше на половину разницы, и плашки стоят
  /// на месте макета.
  static const double _actionsInset =
      DoableMetrics.space4 -
      (kMinInteractiveDimension - DoableMetrics.tapMin) / 2;

  final String title;
  final ConfirmDialogText text;
  final String cancelLabel;
  final String actionLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<DoableColors>()!;
    final shadows = theme.extension<DoableShadows>()!;

    return Dialog(
      // Плоскость с тенью `shadow-float` рисует сам диалог: поверхность
      // Material даёт только тень по высоте подъёма.
      backgroundColor: Colors.transparent,
      elevation: 0,
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(
        horizontal: DoableMetrics.space8,
        vertical: DoableMetrics.space6,
      ),
      semanticsRole: SemanticsRole.alertDialog,
      child: Semantics(
        scopesRoute: true,
        namesRoute: true,
        explicitChildNodes: true,
        label: title,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.raised,
            borderRadius: BorderRadius.circular(DoableMetrics.radiusXl),
            boxShadow: shadows.shadowFloat,
          ),
          // Крупный шрифт и клавиатура, которую ещё скрывает платформа,
          // оставляют диалогу меньше высоты, чем занимает содержимое:
          // текст и действия прокручиваются вместе и остаются доступны.
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              DoableMetrics.space6,
              22,
              DoableMetrics.space6,
              _actionsInset,
            ),
            child: SizedBox(
              width: double.infinity,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: DoableType.title.copyWith(color: colors.ink),
                  ),
                  const SizedBox(height: 6),
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: text.before),
                        TextSpan(
                          text: text.name,
                          style: TextStyle(color: colors.ink),
                        ),
                        TextSpan(text: text.after),
                      ],
                    ),
                    style: DoableType.body.copyWith(color: colors.muted),
                  ),
                  const SizedBox(height: _actionsInset),
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: OverflowBar(
                      spacing: DoableMetrics.space2,
                      overflowSpacing: DoableMetrics.space2,
                      overflowAlignment: OverflowBarAlignment.end,
                      children: [
                        Button.quiet(
                          label: cancelLabel,
                          onPressed: () => Navigator.pop(context, false),
                        ),
                        Button.danger(
                          label: actionLabel,
                          onPressed: () => Navigator.pop(context, true),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
