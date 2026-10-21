import 'package:flutter/material.dart';

import '../doable_colors.dart';
import '../doable_metrics.dart';
import '../doable_shadows.dart';
import '../doable_type.dart';

/// Показывает лист над корневым навигатором, перекрывая всю страницу и панель.
///
/// [builder] строит [Sheet] или композицию на его основе. Потребитель закрывает
/// лист через Navigator.pop с результатом типа [T]; закрытие без выбора даёт null.
/// Барьер, жест закрытия и системное «назад» принадлежат Material:
/// https://api.flutter.dev/flutter/material/showModalBottomSheet.html
Future<T?> showDoableSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) {
  final theme = Theme.of(context);
  final colors =
      theme.extension<DoableColors>() ??
      switch (theme.brightness) {
        Brightness.light => DoableColors.light,
        Brightness.dark => DoableColors.dark,
      };

  return showModalBottomSheet<T>(
    context: context,
    useRootNavigator: true,
    useSafeArea: true,
    isScrollControlled: true,
    requestFocus: true,
    barrierColor: colors.scrim,
    backgroundColor: Colors.transparent,
    elevation: 0,
    shape: const RoundedRectangleBorder(),
    clipBehavior: Clip.none,
    // Лист занимает всю доступную ширину, без ограничения Material 3 в 640 dp.
    constraints: const BoxConstraints(maxWidth: double.infinity),
    showDragHandle: false,
    isDismissible: true,
    enableDrag: true,
    builder: (context) => Padding(
      // SafeArea учитывает системные панели, но не открытую клавиатуру.
      // https://api.flutter.dev/flutter/widgets/MediaQueryData/viewInsets.html
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: builder(context),
    ),
  );
}

/// Лист высотой по содержимому с ручкой, заголовком, пояснением, телом и
/// нижней частью.
///
/// При нехватке высоты прокручивается только тело: шапка остаётся доступной
/// для свайпа, а нижняя часть — видна под телом. Компонент только оформляет
/// содержимое, показом управляет [showDoableSheet].
final class Sheet extends StatelessWidget {
  const Sheet({
    required this.title,
    required this.child,
    this.text,
    this.footer,
    super.key,
  });

  final String title;

  /// Пояснение под заголовком; без него тело следует сразу за заголовком.
  final String? text;
  final Widget child;

  /// Основная кнопка листа на всю ширину, закреплённая под телом вне его
  /// прокрутки; без неё лист заканчивается телом.
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors =
        theme.extension<DoableColors>() ??
        switch (theme.brightness) {
          Brightness.light => DoableColors.light,
          Brightness.dark => DoableColors.dark,
        };
    final shadows =
        theme.extension<DoableShadows>() ??
        switch (theme.brightness) {
          Brightness.light => DoableShadows.light,
          Brightness.dark => DoableShadows.dark,
        };
    const borderRadius = BorderRadius.vertical(
      top: Radius.circular(DoableMetrics.radiusXl),
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: shadows.shadowFloat,
      ),
      child: Material(
        color: colors.raised,
        borderRadius: borderRadius,
        clipBehavior: Clip.antiAlias,
        child: SafeArea(
          top: false,
          minimum: const EdgeInsets.fromLTRB(
            DoableMetrics.space3,
            DoableMetrics.space2,
            DoableMetrics.space3,
            0,
          ),
          // Нижний minimum не прибавлялся бы к системному отступу:
          // https://api.flutter.dev/flutter/widgets/SafeArea/minimum.html
          child: Padding(
            padding: const EdgeInsets.only(bottom: DoableMetrics.space4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: colors.grip,
                      borderRadius: BorderRadius.circular(
                        DoableMetrics.radiusFull,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Semantics(
                  header: true,
                  namesRoute: true,
                  child: Text(
                    title,
                    textAlign: TextAlign.center,
                    style: DoableType.title.copyWith(color: colors.ink),
                  ),
                ),
                if (text case final text?) ...[
                  const SizedBox(height: 2),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: DoableMetrics.space4,
                    ),
                    child: Text(
                      text,
                      textAlign: TextAlign.center,
                      style: DoableType.hint.copyWith(color: colors.muted),
                    ),
                  ),
                ],
                const SizedBox(height: DoableMetrics.space3),
                Flexible(child: SingleChildScrollView(child: child)),
                if (footer case final footer?)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      DoableMetrics.space2,
                      DoableMetrics.space3,
                      DoableMetrics.space2,
                      0,
                    ),
                    child: footer,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
