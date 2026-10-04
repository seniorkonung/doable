import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Замена нижних вставок для области вкладок оболочки.
///
/// Панель основной навигации стоит под областью вкладок и занимает
/// [barHeight] и нижний безопасный отступ. Поэтому содержимое получает
/// данные `MediaQuery`, в которых этот отступ обнулён, а вставка клавиатуры
/// уменьшена на занятую панелью высоту: содержимое заканчивается на большем
/// из высоты клавиатуры и высоты панели, как тело `Scaffold` с нижней
/// панелью. Остальные данные передаются без изменения.
///
/// Высота панели задаётся явно, поэтому измерение после раскладки не
/// требуется. Маршрутов, вкладок и содержимого страниц замена не знает.
final class AppShellTabInsets extends StatelessWidget {
  const AppShellTabInsets({
    required this.barHeight,
    required this.child,
    super.key,
  }) : assert(barHeight >= 0, 'Высота панели не может быть отрицательной.');

  /// Высота панели без нижнего безопасного отступа.
  final double barHeight;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final data = MediaQuery.of(context);
    final keyboard = data.viewInsets.bottom;
    // Панель занимает свою высоту и текущий нижний безопасный отступ.
    final covered = barHeight + data.padding.bottom;
    return MediaQuery(
      data: data
          .removePadding(removeBottom: true)
          .copyWith(
            viewInsets: data.viewInsets.copyWith(
              bottom: math.max(0, keyboard - covered),
            ),
          ),
      child: child,
    );
  }
}
