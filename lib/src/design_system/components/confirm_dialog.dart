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
}) => _showDialog(
  context: context,
  title: title,
  barrierLabel: cancelLabel,
  variant: _Confirm(
    text: text,
    cancelLabel: cancelLabel,
    actionLabel: actionLabel,
  ),
);

/// Показывает над корневым навигатором диалог перед действием, которое
/// сохраняет данные, и возвращает, подтверждено ли оно.
///
/// [title] — вопрос, называющий действие и предмет; он же — название
/// маршрута для экранного диктора. [cancelLabel] — подпись quiet-кнопки
/// отмены и доступное название затемнения, [actionLabel] — подпись основной
/// кнопки, повторяющая глагол вопроса. [warning] — второй абзац цветом
/// `ink`: что при этом не сохранится; без него абзаца нет.
///
/// Действие даёт true, а отмена, касание затемнения и системное «назад» —
/// false.
Future<bool> showPreservingConfirmDialog({
  required BuildContext context,
  required String title,
  required ConfirmDialogText text,
  String? warning,
  required String cancelLabel,
  required String actionLabel,
}) => _showDialog(
  context: context,
  title: title,
  barrierLabel: cancelLabel,
  variant: _Preserving(
    text: text,
    warning: warning,
    cancelLabel: cancelLabel,
    actionLabel: actionLabel,
  ),
);

/// Показывает над корневым навигатором диалог перед уходом с несохранённой
/// работой и возвращает, отменена ли она.
///
/// [title] — вопрос, например «Отменить изменения?»; он же — название
/// маршрута для экранного диктора. [text] — что не сохранится.
/// [discardLabel] — подпись текстовой кнопки, которая отменяет работу,
/// [keepLabel] — подпись основной кнопки, которая её сохраняет, и доступное
/// название затемнения.
///
/// Отмену даёт только текстовая кнопка. Безопасный ответ — сохранить работу:
/// основная кнопка, касание затемнения и системное «назад» дают false.
Future<bool> showDiscardDialog({
  required BuildContext context,
  required String title,
  required String text,
  required String discardLabel,
  required String keepLabel,
}) => _showDialog(
  context: context,
  title: title,
  barrierLabel: keepLabel,
  variant: _Discard(
    text: text,
    discardLabel: discardLabel,
    keepLabel: keepLabel,
  ),
);

Future<bool> _showDialog({
  required BuildContext context,
  required String title,
  required String barrierLabel,
  required _Variant variant,
}) async {
  final colors = Theme.of(context).extension<DoableColors>()!;
  final accepted = await showDialog<bool>(
    context: context,
    useRootNavigator: true,
    barrierColor: colors.scrim,
    barrierLabel: barrierLabel,
    builder: (context) => _ConfirmDialog(title: title, variant: variant),
  );
  return accepted ?? false;
}

/// Вариант диалога: его первый абзац, действия и их место.
sealed class _Variant {
  const _Variant();
}

/// Вопрос перед необратимым действием: quiet-кнопка отмены и
/// danger-кнопка действия в space-2 друг от друга.
final class _Confirm extends _Variant {
  const _Confirm({
    required this.text,
    required this.cancelLabel,
    required this.actionLabel,
  });

  final ConfirmDialogText text;
  final String cancelLabel;
  final String actionLabel;
}

/// Вопрос перед действием, которое сохраняет данные: quiet-кнопка отмены и
/// основная кнопка действия в space-2 друг от друга, а за первым абзацем
/// необязательное предупреждение.
final class _Preserving extends _Variant {
  const _Preserving({
    required this.text,
    required this.warning,
    required this.cancelLabel,
    required this.actionLabel,
  });

  final ConfirmDialogText text;
  final String? warning;
  final String cancelLabel;
  final String actionLabel;
}

/// Вопрос перед уходом с несохранённой работой: текстовая кнопка отмены
/// работы и в space-1 за ней основная кнопка, которая её сохраняет.
final class _Discard extends _Variant {
  const _Discard({
    required this.text,
    required this.discardLabel,
    required this.keepLabel,
  });

  final String text;
  final String discardLabel;
  final String keepLabel;
}

final class _ConfirmDialog extends StatelessWidget {
  const _ConfirmDialog({required this.title, required this.variant});

  /// Поле макета вокруг строки действий высотой 44 за вычетом половины
  /// разницы с областью нажатия кнопок Material, чтобы плашки стояли на
  /// месте макета.
  static double _actionsInset(double gap) =>
      gap - (kMinInteractiveDimension - DoableMetrics.tapMin) / 2;

  final String title;
  final _Variant variant;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<DoableColors>()!;
    final shadows = theme.extension<DoableShadows>()!;

    TextSpan paragraphOf(ConfirmDialogText text) => TextSpan(
      children: [
        TextSpan(text: text.before),
        TextSpan(
          text: text.name,
          style: TextStyle(color: colors.ink),
        ),
        TextSpan(text: text.after),
      ],
    );

    final (
      paragraph,
      warning,
      gap,
      spacing,
      outset,
      actions,
    ) = switch (variant) {
      _Confirm(:final text, :final cancelLabel, :final actionLabel) => (
        paragraphOf(text),
        null,
        DoableMetrics.space4,
        DoableMetrics.space2,
        0.0,
        [
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
      _Preserving(
        :final text,
        :final warning,
        :final cancelLabel,
        :final actionLabel,
      ) =>
        (
          paragraphOf(text),
          warning,
          DoableMetrics.space4,
          DoableMetrics.space2,
          0.0,
          [
            Button.quiet(
              label: cancelLabel,
              onPressed: () => Navigator.pop(context, false),
            ),
            Button.primaryCompact(
              label: actionLabel,
              onPressed: () => Navigator.pop(context, true),
            ),
          ],
        ),
      // Строка действий выходит на 8 правее текста, к краю подписи
      // текстовой кнопки без плашки.
      _Discard(:final text, :final discardLabel, :final keepLabel) => (
        TextSpan(text: text),
        null,
        14.0,
        DoableMetrics.space1,
        8.0,
        [
          Button.textMedium(
            label: discardLabel,
            onPressed: () => Navigator.pop(context, true),
          ),
          Button.primaryCompact(
            label: keepLabel,
            onPressed: () => Navigator.pop(context, false),
          ),
        ],
      ),
    };
    final actionsInset = _actionsInset(gap);

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
            padding: EdgeInsetsDirectional.fromSTEB(
              DoableMetrics.space6,
              22,
              DoableMetrics.space6 - outset,
              actionsInset,
            ),
            child: SizedBox(
              width: double.infinity,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: EdgeInsetsDirectional.only(end: outset),
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
                          paragraph,
                          style: DoableType.body.copyWith(color: colors.muted),
                        ),
                        if (warning != null) ...[
                          const SizedBox(height: DoableMetrics.space2),
                          Text(
                            warning,
                            style: DoableType.body.copyWith(color: colors.ink),
                          ),
                        ],
                      ],
                    ),
                  ),
                  SizedBox(height: actionsInset),
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: OverflowBar(
                      spacing: spacing,
                      overflowSpacing: spacing,
                      overflowAlignment: OverflowBarAlignment.end,
                      children: actions,
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
