import 'package:flutter/material.dart';

import '../doable_colors.dart';
import '../doable_icon.dart';
import '../doable_metrics.dart';
import '../doable_type.dart';

/// Верхняя панель экрана, который отменяется целиком, например экрана выбора:
/// крестик слева и заголовок по центру. Стоит в `Scaffold.appBar` прямо под
/// системным отступом, без фона, линии и тени.
final class TopBar extends StatelessWidget implements PreferredSizeWidget {
  static const double _height = 44;

  /// Поле заголовка с каждой стороны, которое он не занимает, что бы ни
  /// стояло по краям.
  static const double _titleInset = 64;

  const TopBar({
    required this.title,
    required this.closeLabel,
    required this.onClose,
    this.closeKey,
    super.key,
  });

  /// Одна строка; длинный заголовок кончается многоточием.
  final String title;

  /// Доступное название крестика.
  final String closeLabel;
  final VoidCallback onClose;

  /// Ключ крестика, по которому его находят сценарии экрана.
  final Key? closeKey;

  @override
  Size get preferredSize => const Size.fromHeight(_height);

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<DoableColors>()!;

    return SafeArea(
      bottom: false,
      child: SizedBox(
        height: _height,
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: _titleInset),
              child: Center(
                child: Semantics(
                  container: true,
                  header: true,
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: DoableType.title.copyWith(color: colors.ink),
                  ),
                ),
              ),
            ),
            PositionedDirectional(
              start: DoableMetrics.space2,
              top: 0,
              bottom: 0,
              child: MergeSemantics(
                child: Semantics(
                  button: true,
                  label: closeLabel,
                  child: InkResponse(
                    key: closeKey,
                    onTap: onClose,
                    radius: DoableMetrics.tapMin / 2,
                    child: SizedBox.square(
                      dimension: DoableMetrics.tapMin,
                      child: Center(
                        child: DoableIcon(
                          DoableIconData.close,
                          size: DoableMetrics.iconSize,
                          color: colors.ink,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
