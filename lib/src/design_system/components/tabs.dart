import 'dart:math' as math;
import 'dart:ui' show SemanticsRole;

import 'package:flutter/material.dart';

import '../doable_colors.dart';
import '../doable_icon.dart';
import '../doable_metrics.dart';
import '../doable_type.dart';
import '../text_metrics.dart';

/// Вкладка с готовым доступным названием, включающим смысл числа и значка.
final class TabItem<T extends Object> {
  const TabItem({
    required this.id,
    required this.label,
    required this.semanticLabel,
    this.count,
    this.icon,
  }) : assert(count == null || count >= 0);

  final T id;
  final String label;
  final String semanticLabel;
  final int? count;
  final DoableIconData? icon;
}

/// Прокручиваемая полоса вкладок. Выбором и закреплением управляет страница.
final class Tabs<T extends Object> extends StatefulWidget {
  const Tabs({
    required this.items,
    required this.value,
    required this.onChange,
    required this.label,
    this.stuck = false,
    super.key,
  });

  final List<TabItem<T>> items;
  final T value;
  final ValueChanged<T> onChange;
  final String label;
  final bool stuck;

  /// Высота закреплённой полосы для `SliverPersistentHeader`: 52 при обычном
  /// тексте, с ростом пилюль при увеличении системного масштаба.
  static double heightFor(BuildContext context) => _pillHeight(context) + 16;

  static double _pillHeight(BuildContext context) => math.max(
    DoableMetrics.controlHeightSm,
    tallestTextHeight(
          context,
          texts: const ['0'],
          style: DoableType.section,
          maxWidth: double.infinity,
        ) +
        16,
  );

  @override
  State<Tabs<T>> createState() => _TabsState<T>();
}

final class _TabsState<T extends Object> extends State<Tabs<T>> {
  final _scrollController = ScrollController();
  final _itemKeys = <T, GlobalKey>{};
  double? _viewportWidth;
  var _revealScheduled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scheduleReveal();
  }

  @override
  void didUpdateWidget(covariant Tabs<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    _scheduleReveal();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scheduleReveal() {
    if (_revealScheduled) return;
    _revealScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _revealScheduled = false;
      if (!mounted) return;
      final target = _itemKeys[widget.value]?.currentContext
          ?.findRenderObject();
      if (target == null) return;
      // Меняется только горизонтальная позиция: ensureVisible у Scrollable
      // затронул бы также вертикальную прокрутку страницы.
      // https://api.flutter.dev/flutter/widgets/ScrollPosition/ensureVisible.html
      _scrollController.position.ensureVisible(target, alignment: 0.5);
    });
  }

  @override
  Widget build(BuildContext context) {
    assert(
      widget.items.map((item) => item.id).toSet().length == widget.items.length,
    );
    assert(widget.items.any((item) => item.id == widget.value));
    _itemKeys.removeWhere(
      (id, _) => !widget.items.any((item) => item.id == id),
    );
    final colors = Theme.of(context).extension<DoableColors>()!;
    final pillHeight = Tabs._pillHeight(context);
    return Material(
      color: colors.bg,
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          border: widget.stuck
              ? Border(bottom: BorderSide(color: colors.hairline))
              : null,
        ),
        child: SizedBox(
          height: Tabs.heightFor(context),
          child: LayoutBuilder(
            builder: (context, constraints) {
              if (_viewportWidth != constraints.maxWidth) {
                _viewportWidth = constraints.maxWidth;
                _scheduleReveal();
              }
              return Stack(
                children: [
                  SingleChildScrollView(
                    controller: _scrollController,
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(
                      DoableMetrics.space5,
                      DoableMetrics.space1,
                      DoableMetrics.space4,
                      DoableMetrics.space1,
                    ),
                    child: Semantics(
                      container: true,
                      explicitChildNodes: true,
                      role: SemanticsRole.tabBar,
                      label: widget.label,
                      child: Row(
                        spacing: DoableMetrics.space1,
                        children: [
                          for (final item in widget.items)
                            _TabPill(
                              key: _itemKeys.putIfAbsent(
                                item.id,
                                GlobalKey.new,
                              ),
                              item: item,
                              selected: item.id == widget.value,
                              height: pillHeight,
                              onTap: () => widget.onChange(item.id),
                            ),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    width: 16,
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [colors.bg, colors.bgFade],
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 0,
                    top: 0,
                    bottom: 0,
                    width: 28,
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [colors.bgFade, colors.bg],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

final class _TabPill<T extends Object> extends StatefulWidget {
  const _TabPill({
    required this.item,
    required this.selected,
    required this.height,
    required this.onTap,
    super.key,
  });

  final TabItem<T> item;
  final bool selected;
  final double height;
  final VoidCallback onTap;

  @override
  State<_TabPill<T>> createState() => _TabPillState<T>();
}

final class _TabPillState<T extends Object> extends State<_TabPill<T>> {
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

  void _handleHighlightMode(FocusHighlightMode mode) {
    if (_focused) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<DoableColors>()!;
    const radius = BorderRadius.all(Radius.circular(DoableMetrics.radiusFull));
    final showsFocus =
        _focused &&
        FocusManager.instance.highlightMode == FocusHighlightMode.traditional;
    // Роль вкладки и готовое название принадлежат одному узлу:
    // https://api.flutter.dev/flutter/dart-ui/SemanticsRole.html
    return Semantics(
      container: true,
      role: SemanticsRole.tab,
      selected: widget.selected,
      label: widget.item.semanticLabel,
      onTap: widget.onTap,
      child: InkWell(
        onTap: widget.onTap,
        excludeFromSemantics: true,
        borderRadius: radius,
        focusColor: Colors.transparent,
        onFocusChange: (focused) => setState(() => _focused = focused),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: DoableMetrics.space1),
          // Ink сохраняет отклик нажатия над fill:
          // https://api.flutter.dev/flutter/material/InkWell-class.html
          child: Ink(
            decoration: BoxDecoration(
              color: widget.selected ? colors.fill : null,
              borderRadius: radius,
              boxShadow: showsFocus
                  ? [
                      BoxShadow(color: colors.accent, spreadRadius: 4),
                      BoxShadow(color: colors.bg, spreadRadius: 2),
                    ]
                  : null,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minWidth: DoableMetrics.tapMin,
                minHeight: widget.height,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: ExcludeSemantics(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    spacing: 6,
                    children: [
                      Text(
                        widget.item.label,
                        style: DoableType.section.copyWith(
                          color: widget.selected ? colors.ink : colors.muted,
                        ),
                      ),
                      if (widget.item.count case final count?)
                        Text(
                          '$count',
                          style: DoableType.label.copyWith(
                            color: colors.muted,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      if (widget.item.icon case final icon?)
                        DoableIcon(icon, size: 14, color: colors.muted),
                    ],
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
