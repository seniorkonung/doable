import 'package:flutter/material.dart';

import 'app_navigation.dart';
import 'relation_picker_position.dart';

/// Каркас обычной страницы над оболочкой основной навигации.
///
/// Панель занимает [Scaffold.bottomNavigationBar], а на страницах над поиском
/// участника её место отдано [pickerFooter]; тело и сообщения
/// размещает Scaffold с учётом панели, безопасных отступов и клавиатуры.
/// Требует смонтированную оболочку приложения; состояние навигации и сброс
/// истории предоставляет [AppNavigation]. У страницы-задачи свой Scaffold.
final class OrdinaryPageScaffold extends StatelessWidget {
  const OrdinaryPageScaffold({
    this.appBar,
    this.body,
    this.pickerFooter,
    super.key,
  });

  final PreferredSizeWidget? appBar;
  final Widget? body;

  /// Закреплённая нижняя часть страницы над поиском участника.
  final Widget? pickerFooter;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: appBar,
    body: body,
    // https://api.flutter.dev/flutter/material/Scaffold/bottomNavigationBar.html
    bottomNavigationBar: isAboveRelationPicker(context)
        ? pickerFooter
        : const AppNavigation(),
  );
}
