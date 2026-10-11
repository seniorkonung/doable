import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../navigation/app_destination.dart';

@RoutePage()
final class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(AppDestination.home.title(localizations))),
      body: const SizedBox.shrink(),
    );
  }
}
