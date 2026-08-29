import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/app/localization/app_locale_resolution.dart';
import 'package:flutter/material.dart';

void main() {
  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      onGenerateTitle: _appTitle,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      localeListResolutionCallback: resolveAppLocale,
      home: Scaffold(body: Center(child: Text('Hello World!'))),
    );
  }
}

String _appTitle(BuildContext context) => AppLocalizations.of(context).appTitle;
