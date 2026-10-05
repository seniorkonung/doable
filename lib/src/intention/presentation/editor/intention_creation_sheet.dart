import 'package:flutter/material.dart';

/// Компактная модальная нижняя панель создания намерения над страницей, с
/// которой начато создание.
///
/// Панель отвечает только за модальность и геометрию: модальный фон над
/// страницей под ней, высоту по содержимому в пределах доступной области,
/// закреплённые верхнюю и нижнюю части и вход и выход вместе со своим
/// маршрутом. Фон сам маршрут не закрывает: нажатие на него и действие
/// экранного диктора передаются владельцу через [onCloseRequested], а
/// владелец решает, чем закончится запрос закрытия.
final class IntentionCreationSheet extends StatelessWidget {
  const IntentionCreationSheet({
    required this.closeLabel,
    required this.onCloseRequested,
    required this.header,
    required this.fields,
    required this.footer,
    super.key,
  });

  /// Участок страницы под строкой состояния, который панель оставляет
  /// видимым при любой высоте содержимого: контекст, над которым открыто
  /// создание. Это отступ, а не доля экрана.
  static const _visibleContextExtent = 72.0;

  /// Наибольшая ширина панели на широком экране.
  static const _maxWidth = 640.0;

  /// Доступное название модального фона: его действие запрашивает закрытие.
  final String closeLabel;

  /// Запрос закрытия нажатием вне панели или действием экранного диктора.
  final VoidCallback onCloseRequested;

  /// Закреплённая верхняя часть панели.
  final Widget header;

  /// Поля формы. Прокручиваются, когда не помещаются в доступную высоту.
  final Widget fields;

  /// Закреплённая нижняя часть с основным действием формы.
  final Widget footer;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final colors = Theme.of(context).colorScheme;
    final animation =
        ModalRoute.of(context)?.animation ?? kAlwaysCompleteAnimation;
    return Stack(
      fit: StackFit.expand,
      children: [
        // Фон закрывает страницу под панелью от нажатий, а модальный барьер
        // маршрута — от фокуса и экранного диктора.
        FadeTransition(
          opacity: animation,
          child: ModalBarrier(
            color: colors.scrim.withValues(alpha: 0.32),
            semanticsLabel: closeLabel,
            onDismiss: onCloseRequested,
          ),
        ),
        Padding(
          // Панель стоит над клавиатурой и не поднимается выше видимого
          // участка страницы под строкой состояния.
          padding: EdgeInsets.only(
            top: media.padding.top + _visibleContextExtent,
            bottom: media.viewInsets.bottom,
          ),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: SlideTransition(
              position: animation.drive(
                Tween(
                  begin: const Offset(0, 1),
                  end: Offset.zero,
                ).chain(CurveTween(curve: Curves.easeOutCubic)),
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: _maxWidth),
                child: Material(
                  key: const ValueKey('intention-creation-sheet'),
                  color: colors.surfaceContainerLow,
                  elevation: 1,
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(28),
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  // Клавиатура и строка состояния уже учтены положением
                  // панели; внутри остаётся только нижний безопасный отступ.
                  child: MediaQuery(
                    data: media
                        .removePadding(removeTop: true)
                        .removeViewInsets(removeBottom: true),
                    child: SafeArea(
                      top: false,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          header,
                          Flexible(child: SingleChildScrollView(child: fields)),
                          footer,
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
