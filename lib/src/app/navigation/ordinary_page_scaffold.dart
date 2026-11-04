import 'package:flutter/material.dart';

import 'app_navigation.dart';

/// Каркас обычной страницы над оболочкой основной навигации.
///
/// Панель занимает [Scaffold.bottomNavigationBar]; тело и сообщения
/// размещает Scaffold с учётом панели, безопасных отступов и клавиатуры.
/// Требует смонтированную оболочку приложения; состояние навигации и сброс
/// истории предоставляет [AppNavigation]. У страницы-задачи свой Scaffold.
final class OrdinaryPageScaffold extends StatelessWidget {
  const OrdinaryPageScaffold({
    this.appBar,
    this.body,
    this.floatingActionButton,
    this.floatingActionButtonLocation,
    super.key,
  });

  final PreferredSizeWidget? appBar;
  final Widget? body;
  final Widget? floatingActionButton;
  final FloatingActionButtonLocation? floatingActionButtonLocation;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: appBar,
    body: body,
    floatingActionButton: floatingActionButton,
    floatingActionButtonLocation: floatingActionButtonLocation,
    // https://api.flutter.dev/flutter/material/Scaffold/bottomNavigationBar.html
    bottomNavigationBar: const AppNavigation(),
  );
}
