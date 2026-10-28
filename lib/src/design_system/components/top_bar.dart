import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../doable_colors.dart';
import '../doable_icon.dart';
import '../doable_metrics.dart';
import '../doable_type.dart';
import 'button.dart';
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

/// Кнопка-иконка справа на панели страницы, например «⋯» параметров.
final class TopBarAction {
  const TopBarAction({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final DoableIconData icon;

  /// Доступное название кнопки.
  final String label;
  final VoidCallback onPressed;
}

/// Верхняя панель со стрелкой назад или крестиком слева, заголовком по центру
/// и, на странице, кнопкой-иконкой справа, а на экране правки — основной
/// кнопкой справа.
/// Стоит в `Scaffold.appBar` прямо под системным отступом, без фона, линии и тени.
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
  static const double _titleIconSize = 16;
  static const double _titleIconGap = 6;

  /// Панель экрана, который отменяется целиком, с крестиком слева.
  const TopBar({
    required String title,
    required String closeLabel,
    required VoidCallback onClose,
    Key? closeKey,
    super.key,
  }) : title = title,
       titleIcon = null,
       muted = false,
       routeName = title,
       _leading = (
         icon: DoableIconData.close,
         label: closeLabel,
         onTap: onClose,
         key: closeKey,
       ),
       _purpose = null,
       _button = null,
       action = null,
       preferredSize = const Size.fromHeight(_minHeight);

  /// Панель страницы со стрелкой назад, видимым заголовком маршрута и
  /// необязательной кнопкой-иконкой [action] справа.
  const TopBar.back({
    required String title,
    required String backLabel,
    required VoidCallback onBack,
    this.titleIcon,
    this.muted = false,
    this.action,
    super.key,
  }) : title = title,
       routeName = title,
       _leading = (
         icon: DoableIconData.back,
         label: backLabel,
         onTap: onBack,
         key: null,
       ),
       _purpose = null,
       _button = null,
       preferredSize = const Size.fromHeight(_minHeight);

  /// Панель только со стрелкой: [routeName] называет маршрут для диктора,
  /// не создавая видимого или пустого семантического заголовка.
  const TopBar.withoutTitle({
    required this.routeName,
    required String backLabel,
    required VoidCallback onBack,
    super.key,
  }) : title = null,
       titleIcon = null,
       muted = false,
       _leading = (
         icon: DoableIconData.back,
         label: backLabel,
         onTap: onBack,
         key: null,
       ),
       _purpose = null,
       _button = null,
       action = null,
       preferredSize = const Size.fromHeight(_minHeight);

  /// Панель экрана правки со стрелкой назад, заголовком и основной кнопкой
  /// размера sm справа, например «Сохранить».
  ///
  /// [context] — место, где панель передаётся в `Scaffold.appBar`. С крупным
  /// шрифтом кнопка растёт, и высота панели растёт вместе с ней;
  /// потребитель перестраивается при смене масштаба и пересчитывает высоту,
  /// которую выделяет `Scaffold`.
  TopBar.withButton(
    BuildContext context, {
    required String title,
    required String backLabel,
    required VoidCallback onBack,
    required String buttonLabel,
    required VoidCallback? onButtonPressed,
    super.key,
  }) : title = title,
       titleIcon = null,
       muted = false,
       routeName = title,
       _leading = (
         icon: DoableIconData.back,
         label: backLabel,
         onTap: onBack,
         key: null,
       ),
       _purpose = null,
       _button = (label: buttonLabel, onPressed: onButtonPressed),
       action = null,
       preferredSize = Size.fromHeight(
         math.max(
           _minHeight,
           Button.smallHeight(MediaQuery.textScalerOf(context)),
         ),
       );

  /// Панель со строкой назначения под заголовком.
  ///
  /// [context] — место, где панель передаётся в `Scaffold.appBar`. Обе строки
  /// показываются в его системном масштабе текста, и высота панели растёт
  /// по ним; потребитель перестраивается при смене масштаба и пересчитывает
  /// высоту, которую выделяет `Scaffold`.
  TopBar.withPurpose(
    BuildContext context, {
    required String title,
    required String closeLabel,
    required VoidCallback onClose,
    required TopBarPurpose purpose,
    Key? closeKey,
    super.key,
  }) : title = title,
       titleIcon = null,
       muted = false,
       routeName = title,
       _leading = (
         icon: DoableIconData.close,
         label: closeLabel,
         onTap: onClose,
         key: closeKey,
       ),
       _purpose = (
         title: title,
         purpose: purpose,
         textScaler: MediaQuery.textScalerOf(context),
       ),
       _button = null,
       action = null,
       preferredSize = Size.fromHeight(
         _purposeHeight(
           title: title,
           subtitle: purpose.subtitle,
           textScaler: MediaQuery.textScalerOf(context),
         ),
       );

  /// Одна строка; длинный заголовок кончается многоточием. Отсутствует только
  /// в явном варианте [TopBar.withoutTitle].
  final String? title;

  /// Декоративный значок перед заголовком, цвета muted.
  final DoableIconData? titleIcon;

  /// Приглушённый заголовок, например название архивированного намерения.
  final bool muted;

  /// Имя маршрута для диктора, в том числе при отсутствии видимого заголовка.
  final String routeName;

  /// Доступное название кнопки слева.
  String get closeLabel => _leading.label;

  /// Обработчик кнопки слева.
  VoidCallback get onClose => _leading.onTap;

  /// Ключ крестика, по которому его находят сценарии экрана.
  Key? get closeKey => _leading.key;

  final ({DoableIconData icon, String label, VoidCallback onTap, Key? key})
  _leading;
  final ({String title, TopBarPurpose purpose, TextScaler textScaler})?
  _purpose;

  /// Без обработчика кнопка справа выключена и остаётся на своём месте.
  final ({String label, VoidCallback? onPressed})? _button;

  /// Кнопка-иконка справа; есть только у [TopBar.back].
  final TopBarAction? action;

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
    final title = this.title;

    return SafeArea(
      bottom: false,
      child: SizedBox(
        height: preferredSize.height,
        child: Stack(
          children: [
            if (purpose == null)
              Semantics(
                container: true,
                header: title != null,
                // Имя маршрута не требует видимого заголовка:
                // https://api.flutter.dev/flutter/semantics/SemanticsProperties/namesRoute.html
                namesRoute: true,
                label: routeName,
                excludeSemantics: true,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: _titleInset),
                  child: Center(
                    child: title == null
                        ? null
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (titleIcon case final icon?) ...[
                                DoableIcon(
                                  icon,
                                  size: _titleIconSize,
                                  color: colors.muted,
                                ),
                                const SizedBox(width: _titleIconGap),
                              ],
                              Flexible(
                                child: Text(
                                  title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: DoableType.title.copyWith(
                                    color: muted ? colors.muted : colors.ink,
                                  ),
                                ),
                              ),
                            ],
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
                  purpose.title,
                  purpose.purpose,
                  purpose.textScaler,
                ),
              ),
            PositionedDirectional(
              start: DoableMetrics.space2,
              top: 0,
              bottom: 0,
              child: _iconButton(
                colors,
                icon: _leading.icon,
                label: _leading.label,
                onTap: _leading.onTap,
                key: _leading.key,
              ),
            ),
            if (action case final action?)
              PositionedDirectional(
                end: DoableMetrics.space2,
                top: 0,
                bottom: 0,
                child: _iconButton(
                  colors,
                  icon: action.icon,
                  label: action.label,
                  onTap: action.onPressed,
                ),
              ),
            if (_button case final button?)
              PositionedDirectional(
                end: DoableMetrics.space3,
                top: 0,
                bottom: 0,
                child: Center(
                  child: Button.primarySmall(
                    label: button.label,
                    onPressed: button.onPressed,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Область нажатия 44 со значком 24 цвета ink по центру панели.
  Widget _iconButton(
    DoableColors colors, {
    required DoableIconData icon,
    required String label,
    required VoidCallback onTap,
    Key? key,
  }) => Center(
    child: MergeSemantics(
      child: Semantics(
        button: true,
        label: label,
        child: InkResponse(
          key: key,
          onTap: onTap,
          radius: DoableMetrics.tapMin / 2,
          child: SizedBox.square(
            dimension: DoableMetrics.tapMin,
            child: Center(
              child: DoableIcon(
                icon,
                size: DoableMetrics.iconSize,
                color: colors.ink,
              ),
            ),
          ),
        ),
      ),
    ),
  );

  /// Строки показываются в том же масштабе, по которому рассчитана высота.
  Widget _purposeButton(
    DoableColors colors,
    String title,
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
