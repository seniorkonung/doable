import 'package:flutter/material.dart';

import 'doable_colors.dart';
import 'doable_metrics.dart';
import 'doable_shadows.dart';
import 'doable_type.dart';

/// Строит оформление Material из основ Doable для выбранной яркости.
///
/// Роли и темы компонентов задаются совместно:
/// https://api.flutter.dev/flutter/material/ThemeData/ThemeData.html
ThemeData doableTheme(Brightness brightness) {
  final colors = switch (brightness) {
    Brightness.light => DoableColors.light,
    Brightness.dark => DoableColors.dark,
  };
  final shadows = switch (brightness) {
    Brightness.light => DoableShadows.light,
    Brightness.dark => DoableShadows.dark,
  };
  final textTheme = TextTheme(
    displayLarge: DoableType.display,
    displayMedium: DoableType.display,
    displaySmall: DoableType.display,
    headlineLarge: DoableType.pageTitle,
    headlineMedium: DoableType.pageTitle,
    headlineSmall: DoableType.pageTitle,
    titleLarge: DoableType.title,
    titleMedium: DoableType.action,
    titleSmall: DoableType.section,
    bodyLarge: DoableType.field,
    bodyMedium: DoableType.body,
    bodySmall: DoableType.hint,
    labelLarge: DoableType.section,
    labelMedium: DoableType.label,
    labelSmall: DoableType.caption,
  ).apply(bodyColor: colors.ink, displayColor: colors.ink);

  // null оставляет выбранные и недоступные состояния правилам Material 3.
  // https://api.flutter.dev/flutter/widgets/WidgetStateProperty/fromMap.html
  final unselectedMuted = WidgetStateProperty<Color?>.fromMap({
    WidgetState.disabled: null,
    WidgetState.selected: null,
    WidgetState.any: colors.muted,
  });
  final unselectedFill = WidgetStateProperty<Color?>.fromMap({
    WidgetState.disabled: null,
    WidgetState.selected: null,
    WidgetState.any: colors.fill,
  });
  const fieldBorder = OutlineInputBorder(
    borderRadius: BorderRadius.all(Radius.circular(DoableMetrics.radiusSm)),
    borderSide: BorderSide.none,
  );

  return ThemeData(
    colorScheme: ColorScheme(
      brightness: brightness,
      primary: colors.ink,
      onPrimary: colors.bg,
      primaryContainer: colors.fill,
      onPrimaryContainer: colors.ink,
      secondary: colors.ink,
      onSecondary: colors.bg,
      secondaryContainer: colors.fill,
      onSecondaryContainer: colors.ink,
      tertiary: colors.accent,
      onTertiary: colors.onAccent,
      tertiaryContainer: colors.accentSoft,
      onTertiaryContainer: colors.accent,
      error: colors.danger,
      onError: colors.onDanger,
      errorContainer: colors.dangerSoft,
      onErrorContainer: colors.danger,
      surface: colors.bg,
      surfaceDim: colors.bg,
      surfaceBright: colors.bg,
      surfaceContainerLowest: colors.bg,
      surfaceContainerLow: colors.raised,
      surfaceContainer: colors.raised,
      surfaceContainerHigh: colors.raised,
      surfaceContainerHighest: colors.fill,
      onSurface: colors.ink,
      onSurfaceVariant: colors.muted,
      outline: colors.hairline,
      outlineVariant: colors.hairline,
      inverseSurface: colors.ink,
      onInverseSurface: colors.bg,
      inversePrimary: colors.accent,
      scrim: colors.scrim,
      surfaceTint: Colors.transparent,
    ),
    fontFamily: 'Inter',
    textTheme: textTheme,
    extensions: [colors, shadows],
    iconTheme: IconThemeData(color: colors.ink, size: 24),
    iconButtonTheme: IconButtonThemeData(
      style: ButtonStyle(
        foregroundColor: unselectedMuted,
        // ListTile во Flutter 3.47.1 заменяет foregroundColor постоянным
        // цветом строки. iconColor сохраняет выключенное состояние Material 3.
        // https://api.flutter.dev/flutter/material/ButtonStyle/iconColor.html
        iconColor: WidgetStateProperty<Color?>.fromMap({
          WidgetState.disabled: colors.ink.withValues(alpha: 0.38),
        }),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, DoableMetrics.controlHeight),
        padding: const EdgeInsets.symmetric(horizontal: DoableMetrics.space4),
        shape: const StadiumBorder(),
        textStyle: DoableType.section,
        disabledBackgroundColor: colors.fill,
        disabledForegroundColor: colors.grip,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(0, DoableMetrics.controlHeight),
        foregroundColor: colors.accent,
        disabledForegroundColor: colors.grip,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, DoableMetrics.controlHeight),
        backgroundColor: colors.fill,
        foregroundColor: colors.ink,
        iconColor: colors.muted,
        side: BorderSide.none,
        shape: const StadiumBorder(),
      ),
    ),
    cardTheme: CardThemeData(
      color: colors.fill,
      elevation: 0,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(DoableMetrics.radiusLg)),
      ),
    ),
    appBarTheme: AppBarThemeData(
      backgroundColor: colors.bg,
      foregroundColor: colors.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      // Размер наследуется. Полная тема ink/24 совпала бы со стандартной,
      // и AppBar не перекрыл бы общий muted для ведущей кнопки во Flutter 3.47.1.
      // https://api.flutter.dev/flutter/material/AppBar-class.html
      iconTheme: IconThemeData(color: colors.ink),
      actionsIconTheme: IconThemeData(color: colors.ink),
    ),
    dialogTheme: DialogThemeData(
      titleTextStyle: DoableType.title.copyWith(color: colors.ink),
      barrierColor: colors.scrim,
      insetPadding: const EdgeInsets.symmetric(
        horizontal: DoableMetrics.space8,
        vertical: DoableMetrics.space6,
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      modalBarrierColor: colors.scrim,
      showDragHandle: true,
      dragHandleColor: colors.grip,
      dragHandleSize: const Size(36, 4),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: unselectedMuted,
      trackColor: unselectedFill,
      trackOutlineColor: unselectedMuted,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: colors.ink,
      contentTextStyle: DoableType.row.copyWith(color: colors.bg),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(DoableMetrics.radiusLg)),
      ),
      insetPadding: const EdgeInsets.fromLTRB(
        DoableMetrics.space5,
        0,
        DoableMetrics.space5,
        DoableMetrics.space3,
      ),
    ),
    inputDecorationTheme: InputDecorationThemeData(
      filled: true,
      fillColor: colors.fill,
      border: fieldBorder,
      enabledBorder: fieldBorder,
      focusedBorder: fieldBorder,
      disabledBorder: fieldBorder,
      errorBorder: fieldBorder,
      focusedErrorBorder: fieldBorder,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: colors.muted,
      circularTrackColor: colors.hairline,
      strokeWidth: 2,
    ),
    chipTheme: const ChipThemeData(shape: StadiumBorder()),
  );
}
