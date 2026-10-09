import 'package:flutter/material.dart';

import 'app_navigation.dart';

/// Каркас обычной страницы над оболочкой основной навигации.
///
/// Панель всегда занимает [Scaffold.bottomNavigationBar]; тело и сообщения
/// размещает Scaffold с учётом панели, безопасных отступов и клавиатуры.
/// Требует смонтированную оболочку приложения; состояние навигации и сброс
/// истории предоставляет [AppNavigation]. У страницы-задачи свой Scaffold.
final class OrdinaryPageScaffold extends StatelessWidget {
  const OrdinaryPageScaffold({this.appBar, this.body, super.key});

  final PreferredSizeWidget? appBar;
  final Widget? body;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: appBar,
    body: body,
    // https://api.flutter.dev/flutter/material/Scaffold/bottomNavigationBar.html
    bottomNavigationBar: const AppNavigation(),
  );
}
