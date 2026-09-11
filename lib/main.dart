import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/app/app_runtime.dart';
import 'package:doable/src/app/bootstrap/app_bootstrap_shell.dart';
import 'package:doable/src/app/localization/app_locale_resolution.dart';
import 'package:flutter/material.dart';

void main() {
  final runtime = AppRuntime.production();
  runApp(MainApp(runtime: runtime));
}

class MainApp extends StatelessWidget {
  const MainApp({
    required this.runtime,
    this.readyChild = const Scaffold(body: Center(child: Text('Hello World!'))),
    super.key,
  });

  final AppRuntime runtime;
  final Widget readyChild;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      onGenerateTitle: _appTitle,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      localeListResolutionCallback: resolveAppLocale,
      home: AppBootstrapShell(runtime: runtime, child: readyChild),
    );
  }
}

String _appTitle(BuildContext context) => AppLocalizations.of(context).appTitle;
