import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../doable_colors.dart';
import '../doable_metrics.dart';
import '../doable_icon.dart';
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

    final (paragraph, gap, spacing, outset, actions) = switch (variant) {
      _Confirm(:final text, :final cancelLabel, :final actionLabel) => (
        paragraphOf(text),
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
      // Строка действий выходит на 8 правее текста, к краю подписи
      // текстовой кнопки без плашки.
      _Discard(:final text, :final discardLabel, :final keepLabel) => (
        TextSpan(text: text),
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

/// Ответ на вопрос о составе каскадной операции.
enum CascadeDialogResult { cascade, single, cancel }

/// Оформление первого ответа: необратимое удаление или сохранение данных.
enum CascadeActionStyle { danger, primary }

/// Знак перед названием намерения в списке.
enum CascadeListMarker { ring, intention }

/// Способ показа длинного списка; подписи задаёт потребитель.
sealed class CascadeListDisplay {
  const CascadeListDisplay();
}

final class CascadeListAll extends CascadeListDisplay {
  const CascadeListAll();
}

final class CascadeListExpandable extends CascadeListDisplay {
  const CascadeListExpandable(this.label);
  final String label;
}

final class CascadeListSummary extends CascadeListDisplay {
  const CascadeListSummary(this.label);
  final String label;
}

/// Заголовок и упорядоченные названия намерений для вопроса о каскаде.
final class CascadeDialogList {
  const CascadeDialogList({
    required this.title,
    required this.items,
    required this.marker,
    required this.display,
  });

  final String title;
  final List<String> items;
  final CascadeListMarker marker;
  final CascadeListDisplay display;
}

/// Спрашивает о составе операции. Затемнение и системное «назад» отменяют её.
/// [footer] поясняет второй вариант под списками; все подписи задаёт вызывающий.
Future<CascadeDialogResult> showCascadeConfirmDialog({
  required BuildContext context,
  required String title,
  required String text,
  required List<CascadeDialogList> lists,
  required String cascadeLabel,
  String? singleLabel,
  required String cancelLabel,
  required CascadeActionStyle actionStyle,
  String? footer,
}) async {
  final colors = Theme.of(context).extension<DoableColors>()!;
  final result = await showDialog<CascadeDialogResult>(
    context: context,
    useRootNavigator: true,
    barrierColor: colors.scrim,
    barrierLabel: cancelLabel,
    builder: (context) => _CascadeDialog(
      title: title,
      text: text,
      lists: lists,
      footer: footer,
      cascadeLabel: cascadeLabel,
      singleLabel: singleLabel,
      cancelLabel: cancelLabel,
      actionStyle: actionStyle,
    ),
  );
  return result ?? CascadeDialogResult.cancel;
}

final class _CascadeDialog extends StatelessWidget {
  const _CascadeDialog({
    required this.title,
    required this.text,
    required this.lists,
    required this.footer,
    required this.cascadeLabel,
    required this.singleLabel,
    required this.cancelLabel,
    required this.actionStyle,
  });

  final String title;
  final String text;
  final List<CascadeDialogList> lists;
  final String? footer;
  final String cascadeLabel;
  final String? singleLabel;
  final String cancelLabel;
  final CascadeActionStyle actionStyle;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<DoableColors>()!;
    final shadows = Theme.of(context).extension<DoableShadows>()!;
    void answer(CascadeDialogResult result) => Navigator.pop(context, result);
    return Dialog(
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
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 700),
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(
                DoableMetrics.space6,
                22,
                DoableMetrics.space6,
                DoableMetrics.space4,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            title,
                            style: DoableType.title.copyWith(color: colors.ink),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            text,
                            style: DoableType.body.copyWith(
                              color: colors.muted,
                            ),
                          ),
                          for (final list in lists) ...[
                            const SizedBox(height: DoableMetrics.space3),
                            _CascadeList(list: list),
                          ],
                          if (footer case final footer?) ...[
                            const SizedBox(height: DoableMetrics.space3),
                            Text(
                              footer,
                              style: DoableType.body.copyWith(
                                color: colors.ink,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: DoableMetrics.space4),
                  if (singleLabel == null) ...[
                    Button.textMedium(
                      label: cancelLabel,
                      onPressed: () => answer(CascadeDialogResult.cancel),
                    ),
                    const SizedBox(height: DoableMetrics.space1),
                  ],
                  switch (actionStyle) {
                    CascadeActionStyle.danger => Button.danger(
                      label: cascadeLabel,
                      onPressed: () => answer(CascadeDialogResult.cascade),
                    ),
                    CascadeActionStyle.primary => Button.primary(
                      label: cascadeLabel,
                      onPressed: () => answer(CascadeDialogResult.cascade),
                    ),
                  },
                  if (singleLabel case final label?) ...[
                    const SizedBox(height: DoableMetrics.space1),
                    Button.quietBlock(
                      label: label,
                      onPressed: () => answer(CascadeDialogResult.single),
                    ),
                  ],
                  if (singleLabel != null) ...[
                    const SizedBox(height: DoableMetrics.space1),
                    Button.textMedium(
                      label: cancelLabel,
                      onPressed: () => answer(CascadeDialogResult.cancel),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

final class _CascadeList extends StatefulWidget {
  const _CascadeList({required this.list});
  final CascadeDialogList list;

  @override
  State<_CascadeList> createState() => _CascadeListState();
}

final class _CascadeListState extends State<_CascadeList> {
  bool expanded = false;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<DoableColors>()!;
    final list = widget.list;
    final truncated =
        list.items.length > 4 && !expanded && list.display is! CascadeListAll;
    final items = truncated ? list.items.take(4) : list.items;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(list.title, style: DoableType.label.copyWith(color: colors.muted)),
        for (final item in items)
          Padding(
            padding: const EdgeInsetsDirectional.only(
              top: DoableMetrics.space1,
            ),
            child: Row(
              children: [
                switch (list.marker) {
                  CascadeListMarker.ring => Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: colors.accent, width: 2),
                    ),
                  ),
                  CascadeListMarker.intention => DoableIcon(
                    DoableIconData.intention,
                    size: 16,
                    color: colors.ink,
                  ),
                },
                const SizedBox(width: DoableMetrics.space2),
                Expanded(
                  child: Text(
                    item,
                    style: DoableType.row.copyWith(color: colors.ink),
                  ),
                ),
              ],
            ),
          ),
        if (truncated)
          switch (list.display) {
            CascadeListExpandable(:final label) => Button.text(
              label: label,
              semanticLabel: label,
              onPressed: () => setState(() => expanded = true),
            ),
            CascadeListSummary(:final label) => Text(
              label,
              style: DoableType.hint.copyWith(color: colors.muted),
            ),
            CascadeListAll() => const SizedBox.shrink(),
          },
      ],
    );
  }
}
