import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../data_transfer/presentation/settings_data_section.dart';
import '../../design_system/doable_metrics.dart';
import '../navigation/ordinary_page_scaffold.dart';

/// Страница «Настройки» — обычная страница поверх Главной с разделом
/// «Данные».
@RoutePage()
final class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) => OrdinaryPageScaffold(
    appBar: AppBar(title: Text(AppLocalizations.of(context).settingsTitle)),
    body: SafeArea(
      child: ListView(
        // Строки раздела сами отступают на space2, поэтому их значки стоят в
        // 20 логических пикселях от края, как в макете.
        padding: const EdgeInsets.fromLTRB(
          DoableMetrics.space3,
          DoableMetrics.space2,
          DoableMetrics.space3,
          DoableMetrics.space6,
        ),
        children: const [SettingsDataSection()],
      ),
    ),
  );
}
