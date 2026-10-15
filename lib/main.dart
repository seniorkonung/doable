import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/app/app_runtime.dart';
import 'package:doable/src/app/bootstrap/app_bootstrap_shell.dart';
import 'package:doable/src/app/localization/app_locale_resolution.dart';
import 'package:doable/src/app/routing/app_router_provider.dart';
import 'package:doable/src/design_system/doable_theme.dart';
import 'package:doable/src/graph/presentation/graph_operation_presenter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (defaultTargetPlatform == TargetPlatform.android) {
    // На API 29–34 edge-to-edge включается явно; API 24–28 его игнорируют.
    // https://api.flutter.dev/flutter/services/SystemUiMode.html
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }
  final runtime = AppRuntime.production();
  runApp(MainApp(runtime: runtime));
}

class MainApp extends StatelessWidget {
  const MainApp({required this.runtime, super.key});

  final AppRuntime runtime;

  @override
  Widget build(BuildContext context) {
    return AppBootstrapShell(runtime: runtime, child: const _ReadyApp());
  }
}

final class _ReadyApp extends ConsumerWidget {
  const _ReadyApp();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    return MaterialApp.router(
      theme: doableTheme(Brightness.light),
      darkTheme: doableTheme(Brightness.dark),
      themeMode: ThemeMode.system,
      onGenerateTitle: _appTitle,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      localeListResolutionCallback: resolveAppLocale,
      routerConfig: router.config(),
      builder: (context, child) =>
          GraphOperationPresenter(child: child ?? const SizedBox.shrink()),
    );
  }
}

String _appTitle(BuildContext context) => AppLocalizations.of(context).appTitle;
