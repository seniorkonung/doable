import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/semantics.dart';

import '../doable_colors.dart';
import '../doable_icon.dart';
import '../doable_metrics.dart';
import '../doable_shadows.dart';
import '../doable_type.dart';

/// Пункт всплывающего меню: значение, которое возвращает его выбор, иконка и
/// название. Название служит доступным названием пункта без подсказки,
/// поэтому должно быть понятно само по себе.
final class PopupMenuAction<T> {
  const PopupMenuAction({
    required this.value,
    required this.icon,
    required this.name,
  });

  final T value;
  final DoableIconData icon;
  final String name;
}

/// Показывает всплывающее меню у удерживаемой строки [row] над корневым
/// навигатором.
///
/// Левый край меню выровнен с содержимым строки, которое отстоит от её начала
/// на [contentInset]. Меню стоит на 4 под строкой, а без места снизу — на 4
/// над ней. [label] — доступное название меню, называющее строку.
/// Разрушительное действие [destructive] стоит после [actions] и окрашено
/// `danger`.
///
/// Экран не затемняется. Выбор пункта возвращает его значение, а касание вне
/// меню и системное «назад» закрывают только меню и дают null; барьер,
/// «назад» и семантику маршрута даёт Material:
/// https://api.flutter.dev/flutter/material/showMenu.html
Future<T?> showPopupMenu<T>({
  required BuildContext row,
  required double contentInset,
  required String label,
  required List<PopupMenuAction<T>> actions,
  PopupMenuAction<T>? destructive,
}) {
  assert(
    actions.isNotEmpty || destructive != null,
    'Меню без пунктов не показывается.',
  );
  final navigator = Navigator.of(row, rootNavigator: true);
  final overlay = navigator.overlay!.context.findRenderObject()! as RenderBox;
  // Строка, которую убрали из дерева, пока меню открыто, оставляет меню там,
  // где оно стояло.
  var rowRect = _rectIn(overlay, row)!;
  final items = [
    for (final action in actions) (action: action, destructive: false),
    if (destructive != null) (action: destructive, destructive: true),
  ];

  return showMenu<T>(
    context: row,
    useRootNavigator: true,
    semanticLabel: label,
    positionBuilder: (context, constraints) {
      final placed = rowRect = _rectIn(overlay, row) ?? rowRect;
      // Когда в одном кадре меняются раскладки строки и меню, например при
      // скрытии клавиатуры, маршрут меню может разложиться раньше строки.
      // Поэтому после кадра меню перестраивается, если строка сместилась.
      SchedulerBinding.instance.addPostFrameCallback((_) {
        final current = _rectIn(overlay, row);
        if (context.mounted && current != null && current != placed) {
          (context as Element).markNeedsBuild();
        }
      });
      // Маршрут меню убирает отступы из MediaQuery построителя положения,
      // а сам удерживает меню в их пределах.
      final screenPadding = MediaQuery.paddingOf(navigator.context);
      final height = _PopupMenuPanel.heightOf(
        items.map((item) => item.action.name),
        textScaler: MediaQuery.textScalerOf(context),
        textDirection: Directionality.of(context),
      );
      final below = placed.bottom + _PopupMenuPanel.gap;
      final bottomLimit =
          constraints.maxHeight - _menuScreenMargin - screenPadding.bottom;
      final top = below + height <= bottomLimit
          ? below
          : placed.top - _PopupMenuPanel.gap - height;
      final left = placed.left + contentInset;
      return RelativeRect.fromLTRB(
        left,
        top,
        constraints.maxWidth - left,
        constraints.maxHeight - top,
      );
    },
    // Плоскость с обводкой и тенью `shadow-float` рисует сама панель:
    // поверхность Material даёт только тень по высоте подъёма.
    color: Colors.transparent,
    elevation: 0,
    shadowColor: Colors.transparent,
    surfaceTintColor: Colors.transparent,
    shape: const RoundedRectangleBorder(),
    menuPadding: EdgeInsets.zero,
    constraints: const BoxConstraints.tightFor(width: _PopupMenuPanel.width),
    items: [_PopupMenuPanel<T>(items)],
  );
}

/// Прямоугольник строки [row] в координатах [overlay] или null, если строки
/// больше нет в дереве.
Rect? _rectIn(RenderBox overlay, BuildContext row) {
  if (!row.mounted) return null;
  final rowBox = row.findRenderObject();
  if (rowBox is! RenderBox || !rowBox.attached) return null;
  return MatrixUtils.transformRect(
    rowBox.getTransformTo(overlay),
    Offset.zero & rowBox.size,
  );
}

/// Поле Material от краёв экрана, в пределах которого стоит меню:
/// https://github.com/flutter/flutter/blob/stable/packages/flutter/lib/src/material/popup_menu.dart
const double _menuScreenMargin = 8;

typedef _PopupMenuItem<T> = ({PopupMenuAction<T> action, bool destructive});

/// Плоскость меню со всеми пунктами — единственный элемент маршрута Material.
final class _PopupMenuPanel<T> extends PopupMenuEntry<T> {
  const _PopupMenuPanel(this.items);

  static const double width = 228;
  static const double gap = DoableMetrics.space1;
  static const double _padding = 6;
  static const double _radius = 20;
  static const double _itemMinHeight = 48;
  static const double _iconSize = 22;
  static const double _nameWidth =
      width -
      2 * _padding -
      2 * DoableMetrics.space3 -
      _iconSize -
      DoableMetrics.space3;

  final List<_PopupMenuItem<T>> items;

  /// Высота меню до его раскладки: положение над строкой зависит от неё,
  /// а длинные названия при крупном шрифте переносятся и растят пункты.
  static double heightOf(
    Iterable<String> names, {
    required TextScaler textScaler,
    required TextDirection textDirection,
  }) {
    var height = 2 * _padding;
    for (final name in names) {
      final painter = TextPainter(
        text: TextSpan(text: name, style: DoableType.action),
        textScaler: textScaler,
        textDirection: textDirection,
      )..layout(maxWidth: _nameWidth);
      height += math.max(
        _itemMinHeight,
        painter.height + 2 * DoableMetrics.space3,
      );
      painter.dispose();
    }
    return height;
  }

  /// Material читает высоту только для начального пункта, которого у меню
  /// нет.
  @override
  double get height => 2 * _padding + items.length * _itemMinHeight;

  @override
  bool represents(T? value) => false;

  @override
  State<_PopupMenuPanel<T>> createState() => _PopupMenuPanelState<T>();
}

final class _PopupMenuPanelState<T> extends State<_PopupMenuPanel<T>> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<DoableColors>()!;
    final shadows = theme.extension<DoableShadows>()!;
    final borderRadius = BorderRadius.circular(_PopupMenuPanel._radius);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.raised,
        borderRadius: borderRadius,
        // В макете обводка — тень без смещения снаружи плоскости.
        border: Border.all(
          color: colors.hairline,
          strokeAlign: BorderSide.strokeAlignOutside,
        ),
        boxShadow: shadows.shadowFloat,
      ),
      child: Padding(
        padding: const EdgeInsets.all(_PopupMenuPanel._padding),
        child: Material(
          type: MaterialType.transparency,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final item in widget.items)
                _item(
                  item.action,
                  item.destructive ? colors.danger : colors.ink,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _item(PopupMenuAction<T> action, Color color) => MergeSemantics(
    child: Semantics(
      role: SemanticsRole.menuItem,
      button: true,
      child: InkWell(
        onTap: () => Navigator.pop(context, action.value),
        borderRadius: BorderRadius.circular(DoableMetrics.radiusMd),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: _PopupMenuPanel._itemMinHeight,
          ),
          child: Padding(
            padding: const EdgeInsets.all(DoableMetrics.space3),
            child: Row(
              children: [
                DoableIcon(
                  action.icon,
                  size: _PopupMenuPanel._iconSize,
                  color: color,
                ),
                const SizedBox(width: DoableMetrics.space3),
                Expanded(
                  child: Text(
                    action.name,
                    style: DoableType.action.copyWith(color: color),
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
