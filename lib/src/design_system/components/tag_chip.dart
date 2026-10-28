import 'package:flutter/material.dart';

import '../doable_colors.dart';
import '../doable_icon.dart';
import '../doable_metrics.dart';
import '../doable_type.dart';
import 'tag_dot.dart';

/// Тег как чип: точка цвета и название. Малый чип стоит в строке списка
/// и не кнопка: нажатие принадлежит строке, которая его показывает. Чип формы
/// — пилюля с крестиком, который снимает тег.
final class TagChip extends StatelessWidget {
  static const double _mediumRadius = 18;
  static const double _removeWidth = 34;
  static const double _removeIconSize = 16;

  /// Малый чип на заливке `fill` строки, поэтому его фон — `bg`.
  const TagChip.small({
    required this.name,
    required this.color,
    this.strong = false,
    super.key,
  }) : _remove = null;

  /// Чип формы на фоне страницы с крестиком в конце пилюли. Без обработчика
  /// крестик недоступен и остаётся на своём месте.
  const TagChip.medium({
    required this.name,
    required this.color,
    required String removeLabel,
    required VoidCallback? onRemove,
    Key? removeKey,
    super.key,
  }) : strong = false,
       _remove = (label: removeLabel, onRemove: onRemove, key: removeKey);

  final String name;
  final DoableTagColor? color;

  /// Название цвета `ink` у тега, которого требует фильтр; только у малого
  /// чипа, у чипа формы название всегда `ink`.
  final bool strong;

  /// Крестик чипа формы; у малого чипа его нет. Ключ стоит на области
  /// нажатия крестика, по нему крестик находят сценарии экрана.
  final ({String label, VoidCallback? onRemove, Key? key})? _remove;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<DoableColors>()!;

    return switch (_remove) {
      null => _small(colors),
      final remove => _medium(colors, remove),
    };
  }

  Widget _small(DoableColors colors) => DecoratedBox(
    decoration: BoxDecoration(
      color: colors.bg,
      borderRadius: BorderRadius.circular(DoableMetrics.radiusXs),
    ),
    child: Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(
        7,
        1,
        DoableMetrics.space2,
        1,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TagDot(color: color, size: TagDotSize.small),
          const SizedBox(width: 5),
          // Слишком широкое название обрезает край, а не переносит.
          Flexible(
            child: Text(
              name,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.clip,
              style: DoableType.caption.copyWith(
                color: strong ? colors.ink : colors.muted,
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _medium(
    DoableColors colors,
    ({String label, VoidCallback? onRemove, Key? key}) remove,
  ) => DecoratedBox(
    decoration: BoxDecoration(
      color: colors.fill,
      borderRadius: BorderRadius.circular(_mediumRadius),
    ),
    child: ConstrainedBox(
      constraints: const BoxConstraints(
        minHeight: DoableMetrics.controlHeightSm,
      ),
      // Область крестика тянется на всю высоту пилюли, когда название
      // переносится на несколько строк.
      child: IntrinsicHeight(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Длинное название переносится внутри пилюли, и пилюля не выходит
            // за ширину строки.
            Flexible(
              child: Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(
                  DoableMetrics.space3,
                  DoableMetrics.space2,
                  2,
                  DoableMetrics.space2,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  spacing: 6,
                  children: [
                    TagDot(color: color, size: TagDotSize.medium),
                    Flexible(
                      child: Text(
                        name,
                        style: DoableType.row.copyWith(color: colors.ink),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            _RemoveButton(
              key: remove.key,
              label: remove.label,
              onRemove: remove.onRemove,
            ),
          ],
        ),
      ),
    ),
  );
}

/// Крестик чипа формы; фокус клавиатуры рисует `focus-ring` вокруг значка.
final class _RemoveButton extends StatefulWidget {
  const _RemoveButton({required this.label, required this.onRemove, super.key});

  final String label;
  final VoidCallback? onRemove;

  @override
  State<_RemoveButton> createState() => _RemoveButtonState();
}

final class _RemoveButtonState extends State<_RemoveButton> {
  var _focused = false;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addHighlightModeListener(_handleHighlightMode);
  }

  @override
  void dispose() {
    FocusManager.instance.removeHighlightModeListener(_handleHighlightMode);
    super.dispose();
  }

  // Кольцо фокуса нужно только при управлении с клавиатуры.
  void _handleHighlightMode(FocusHighlightMode mode) {
    if (_focused) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<DoableColors>()!;
    final showsFocus =
        _focused &&
        FocusManager.instance.highlightMode == FocusHighlightMode.traditional;

    return MergeSemantics(
      child: Semantics(
        button: true,
        enabled: widget.onRemove != null,
        label: widget.label,
        child: InkWell(
          onTap: widget.onRemove,
          borderRadius: const BorderRadiusDirectional.horizontal(
            end: Radius.circular(TagChip._mediumRadius),
          ).resolve(Directionality.of(context)),
          focusColor: Colors.transparent,
          onFocusChange: (focused) => setState(() => _focused = focused),
          child: SizedBox(
            width: TagChip._removeWidth,
            child: Padding(
              padding: const EdgeInsetsDirectional.only(
                end: DoableMetrics.space1,
              ),
              child: Center(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: showsFocus
                        ? [
                            BoxShadow(color: colors.accent, spreadRadius: 4),
                            BoxShadow(color: colors.bg, spreadRadius: 2),
                          ]
                        : null,
                  ),
                  child: DoableIcon(
                    DoableIconData.closeSmall,
                    size: TagChip._removeIconSize,
                    color: colors.muted,
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
