import 'package:auto_route/auto_route.dart';
import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/app/navigation/app_destination.dart';
import 'package:doable/src/app/routing/app_router.gr.dart';
import 'package:flutter/material.dart';

/// Окружение отдельной обычной страницы с настоящей оболочкой и вкладками.
///
/// Пустые корневые страницы не читают репозиторий проверяемой страницы.
/// Интеграционные сценарии используют AppRouter и полные корневые страницы.
final class OrdinaryPageTestApp extends StatefulWidget {
  const OrdinaryPageTestApp({
    required this.home,
    this.locale = const Locale('en'),
    this.builder,
    super.key,
  });

  final Widget home;
  final Locale locale;
  final TransitionBuilder? builder;

  @override
  State<OrdinaryPageTestApp> createState() => _OrdinaryPageTestAppState();
}

final class _OrdinaryPageTestAppState extends State<OrdinaryPageTestApp> {
  // https://pub.dev/documentation/auto_route/11.1.0/auto_route/RootStackRouter/RootStackRouter.build.html
  late final _router = RootStackRouter.build(
    routes: [
      AutoRoute(
        page: AppShellRoute.page,
        initial: true,
        children: [
          for (final destination in AppDestination.values)
            NamedRouteDef(
              name: destination.page.name,
              builder: (_, _) => const Scaffold(),
            ),
        ],
      ),
      NamedRouteDef(name: 'TestOrdinaryRoute', builder: (_, _) => widget.home),
    ],
  );

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp.router(
    locale: widget.locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    builder: widget.builder,
    routerConfig: _router.config(
      deepLinkBuilder: (_) => DeepLink([
        const AppShellRoute(),
        const NamedRoute('TestOrdinaryRoute'),
      ]),
    ),
  );
}
