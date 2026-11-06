import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../app/navigation/ordinary_page_scaffold.dart';
import '../../../design_system/components/scroll_top_button.dart';
import '../../../shared/domain/calendar_date.dart';
import 'action_day_body.dart';
import 'action_day_instance.dart';

@RoutePage()
final class ActionDayDatePage extends StatefulWidget {
  const ActionDayDatePage({required this.date, super.key});

  final CalendarDate date;

  @override
  State<ActionDayDatePage> createState() => _ActionDayDatePageState();
}

final class _ActionDayDatePageState extends State<ActionDayDatePage> {
  late final ActionDayInstance _instance;

  @override
  void initState() {
    super.initState();
    _instance = ActionDayInstance(initialDate: widget.date);
  }

  @override
  Widget build(BuildContext context) => ActionDayBody(
    key: ObjectKey(_instance),
    instance: _instance,
    scaffoldBuilder: (body, scrollTopButton) => OrdinaryPageScaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context).appDestinationActions),
      ),
      body: body,
      floatingActionButton: scrollTopButton,
      floatingActionButtonLocation: const ScrollTopButtonLocation(),
    ),
  );
}
