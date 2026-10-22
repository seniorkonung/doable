import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../doable_colors.dart';
import '../doable_icon.dart';
import '../doable_metrics.dart';
import '../doable_shadows.dart';
import '../doable_type.dart';
import 'tag_dot.dart';

/// Отметка тега в строке при выборе тегов намерения.
enum TagRowMark { none, checked }

/// Фон строки: без фона, удерживаемая для меню или поднятая при
/// перетаскивании.
enum TagRowGround { none, held, lifted }

/// Ручка перестановки слева от точки цвета.
sealed class TagRowHandle {
  const TagRowHandle();
}

/// Ручка скрыта, но сохраняет место, поэтому точка и название не смещаются.
final class TagRowHiddenHandle extends TagRowHandle {
  const TagRowHiddenHandle();
}

/// Ручка начинает перетаскивание элемента [index] ближайшего
/// переставляемого списка; выключенная ручка видна, но не перетаскивает.
final class TagRowDragHandle extends TagRowHandle {
  const TagRowDragHandle({required this.index, required this.enabled});

  final int index;
  final bool enabled;
}

/// Действие меню тега, доступное экранному диктору без удержания.
typedef TagRowMenuAction = ({String label, VoidCallback onInvoke});

/// Меню тега, которое потребитель открывает по удержанию строки
/// или контекстному щелчку.
final class TagRowMenu {
  const TagRowMenu({
    required this.holdHint,
    required this.onOpen,
    required this.actions,
  });

  /// Подсказка диктора о том, что удержание открывает действия тега.
  final String holdHint;
  final VoidCallback onOpen;
  final List<TagRowMenuAction> actions;
}

/// Строка тега в панели тегов: ручка, точка цвета, полное название и
/// отметка. Название переносится без обрезки, а высота растёт от
/// минимальных 48 dp.
final class TagRow extends StatelessWidget {
  static const double _minHeight = 48;
  static const double _handleWidth = 40;

  /// Отступ точки и названия от начала строки: по нему потребитель
  /// выравнивает меню тега.
  static const double contentInset = _handleWidth;

  // Действия кешируются по доступному названию согласно контракту Flutter:
  // https://api.flutter.dev/flutter/semantics/CustomSemanticsAction-class.html
  static final _menuActions = <String, CustomSemanticsAction>{};

  const TagRow({
    required this.name,
    required this.color,
    required this.mark,
    required this.label,
    required this.handle,
    required this.onPressed,
    this.ground = TagRowGround.none,
    this.menu,
    super.key,
  });

  final String name;
  final DoableTagColor? color;
  final TagRowMark mark;

  /// Доступное название строки вместо названия тега. Отметку в нём не
  /// повторяют: диктор объявляет её состоянием отметки строки из [mark].
  final String label;

  final TagRowHandle handle;

  /// Без обработчика строка не принимает нажатие, а экранный диктор
  /// объявляет её недоступной; вид строки не меняется.
  final VoidCallback? onPressed;

  final TagRowGround ground;

  /// Без меню строка не реагирует на удержание.
  final TagRowMenu? menu;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<DoableColors>()!;
    final shadows = theme.extension<DoableShadows>()!;
    final borderRadius = BorderRadius.circular(DoableMetrics.radiusSm);
    final menu = this.menu;

    return MergeSemantics(
      child: Semantics(
        label: label,
        hint: menu?.holdHint,
        checked: mark == TagRowMark.checked,
        enabled: onPressed != null,
        customSemanticsActions: menu == null
            ? null
            : {
                for (final action in menu.actions)
                  _menuActions.putIfAbsent(
                    action.label,
                    () => CustomSemanticsAction(label: action.label),
                  ): action.onInvoke,
              },
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: switch (ground) {
              TagRowGround.none => null,
              TagRowGround.held => colors.fill,
              TagRowGround.lifted => colors.raised,
            },
            borderRadius: borderRadius,
            boxShadow: ground == TagRowGround.lifted
                ? shadows.shadowFloat
                : null,
          ),
          child: Material(
            type: MaterialType.transparency,
            borderRadius: borderRadius,
            clipBehavior: Clip.antiAlias,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: _minHeight),
              // Ручка и область нажатия занимают всю высоту строки,
              // которую задаёт перенесённое название.
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _handle(colors),
                    Expanded(
                      child: InkWell(
                        onTap: onPressed,
                        onLongPress: menu?.onOpen,
                        onSecondaryTap: menu?.onOpen,
                        child: Padding(
                          padding: const EdgeInsetsDirectional.only(
                            end: DoableMetrics.space3,
                          ),
                          child: Row(
                            children: [
                              TagDot(color: color, size: TagDotSize.large),
                              const SizedBox(width: DoableMetrics.space3),
                              Expanded(
                                // Название читает доступное название строки.
                                child: ExcludeSemantics(
                                  child: Text(
                                    name,
                                    style: DoableType.action.copyWith(
                                      color: colors.ink,
                                    ),
                                  ),
                                ),
                              ),
                              if (mark == TagRowMark.checked) ...[
                                const SizedBox(width: DoableMetrics.space3),
                                DoableIcon(
                                  DoableIconData.check,
                                  size: 20,
                                  color: colors.accent,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _handle(DoableColors colors) => switch (handle) {
    TagRowHiddenHandle() => const SizedBox(width: _handleWidth),
    TagRowDragHandle(:final index, :final enabled) =>
      ReorderableDragStartListener(
        index: index,
        enabled: enabled,
        // Заливка делает нажимаемой всю область ручки, а не только точки.
        child: ColoredBox(
          color: Colors.transparent,
          child: SizedBox(
            width: _handleWidth,
            child: Padding(
              padding: const EdgeInsetsDirectional.only(
                start: DoableMetrics.space2,
              ),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: DoableIcon(
                  DoableIconData.grip,
                  size: 16,
                  color: colors.grip,
                ),
              ),
            ),
          ),
        ),
      ),
  };
}
