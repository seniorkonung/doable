import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../doable_colors.dart';
import '../doable_icon.dart';
import '../doable_metrics.dart';
import '../doable_type.dart';
import 'path_glyph.dart';

/// Отметка перед строкой назначения: какое поле связи выбирается.
enum TopBarPurposeMark { sourceField, relatedField }

/// Строка назначения под заголовком панели: зачем открыт экран. Вместе с
/// заголовком она — одна кнопка, которая показывает это назначение целиком.
final class TopBarPurpose {
  const TopBarPurpose({
    required this.subtitle,
    required this.label,
    required this.expanded,
    required this.onOpen,
    this.mark,
  });

  /// Одна строка; не поместившийся текст кончается многоточием.
  final String subtitle;

  /// Пунктирный глиф поля перед строкой. Диктор его не слышит: роль уже
  /// названа словами в строке и в [label].
  final TopBarPurposeMark? mark;

  /// Доступное название общей кнопки заголовка и строки.
  final String label;

  /// Открыто ли то, что показывает кнопка.
  final bool expanded;
  final VoidCallback onOpen;
}

/// Верхняя панель экрана, который отменяется целиком, например экрана выбора:
/// крестик слева и заголовок по центру. Стоит в `Scaffold.appBar` прямо под
/// системным отступом, без фона, линии и тени.
final class TopBar extends StatelessWidget implements PreferredSizeWidget {
  static const double _minHeight = DoableMetrics.tapMin;

  /// Поле заголовка с каждой стороны, которое он не занимает, что бы ни
  /// стояло по краям.
  static const double _titleInset = 64;

  /// Поле кнопки заголовка и строки назначения с каждой стороны.
  static const double _purposeInset = 56;
  static const double _chevronSize = 12;
  static const double _chevronGap = 5;
  static const double _markSize = 12;
  static const double _markGap = 5;

  const TopBar({
    required this.title,
    required this.closeLabel,
    required this.onClose,
    this.closeKey,
    super.key,
  }) : _purpose = null,
       preferredSize = const Size.fromHeight(_minHeight);

  /// Панель со строкой назначения под заголовком.
  ///
  /// [context] — место, где панель передаётся в `Scaffold.appBar`. Обе строки
  /// показываются в его системном масштабе текста, и высота панели растёт
  /// по ним; потребитель перестраивается при смене масштаба и пересчитывает
  /// высоту, которую выделяет `Scaffold`.
  TopBar.withPurpose(
    BuildContext context, {
    required this.title,
    required this.closeLabel,
    required this.onClose,
    required TopBarPurpose purpose,
    this.closeKey,
    super.key,
  }) : _purpose = (
         purpose: purpose,
         textScaler: MediaQuery.textScalerOf(context),
       ),
       preferredSize = Size.fromHeight(
         _purposeHeight(
           title: title,
           subtitle: purpose.subtitle,
           textScaler: MediaQuery.textScalerOf(context),
         ),
       );

  /// Одна строка; длинный заголовок кончается многоточием.
  final String title;

  /// Доступное название крестика.
  final String closeLabel;
  final VoidCallback onClose;

  /// Ключ крестика, по которому его находят сценарии экрана.
  final Key? closeKey;

  final ({TopBarPurpose purpose, TextScaler textScaler})? _purpose;

  @override
  final Size preferredSize;

  /// Не меньше области нажатия и не ниже обеих строк в масштабе [textScaler].
  static double _purposeHeight({
    required String title,
    required String subtitle,
    required TextScaler textScaler,
  }) => math.max(
    _minHeight,
    _lineHeight(title, DoableType.title, textScaler) +
        _lineHeight(subtitle, DoableType.hint, textScaler),
  );

  static double _lineHeight(
    String text,
    TextStyle style,
    TextScaler textScaler,
  ) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
      maxLines: 1,
    )..layout();
    try {
      return painter.height;
    } finally {
      painter.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<DoableColors>()!;
    final purpose = _purpose;

    return SafeArea(
      bottom: false,
      child: SizedBox(
        height: preferredSize.height,
        child: Stack(
          children: [
            if (purpose == null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: _titleInset),
                child: Center(
                  child: Semantics(
                    container: true,
                    header: true,
                    namesRoute: true,
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: DoableType.title.copyWith(color: colors.ink),
                    ),
                  ),
                ),
              )
            else
              Positioned(
                left: _purposeInset,
                right: _purposeInset,
                top: 0,
                bottom: 0,
                child: _purposeButton(
                  colors,
                  purpose.purpose,
                  purpose.textScaler,
                ),
              ),
            PositionedDirectional(
              start: DoableMetrics.space2,
              top: 0,
              bottom: 0,
              child: Center(
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
            ),
          ],
        ),
      ),
    );
  }

  /// Строки показываются в том же масштабе, по которому рассчитана высота.
  Widget _purposeButton(
    DoableColors colors,
    TopBarPurpose purpose,
    TextScaler textScaler,
  ) => MergeSemantics(
    child: Semantics(
      button: true,
      namesRoute: true,
      label: purpose.label,
      expanded: purpose.expanded,
      child: InkWell(
        onTap: purpose.onOpen,
        child: ExcludeSemantics(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textScaler: textScaler,
                style: DoableType.title.copyWith(color: colors.ink),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (purpose.mark case final mark?) ...[
                    PathGlyph(
                      shape: switch (mark) {
                        TopBarPurposeMark.sourceField => PathGlyphShape.diamond,
                        TopBarPurposeMark.relatedField => PathGlyphShape.ring,
                      },
                      outline: PathGlyphOutline.dashed,
                      size: _markSize,
                      color: colors.muted,
                    ),
                    const SizedBox(width: _markGap),
                  ],
                  Flexible(
                    child: Text(
                      purpose.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textScaler: textScaler,
                      style: DoableType.hint.copyWith(color: colors.muted),
                    ),
                  ),
                  const SizedBox(width: _chevronGap),
                  DoableIcon(
                    DoableIconData.chevronDown,
                    size: _chevronSize,
                    color: colors.muted,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
