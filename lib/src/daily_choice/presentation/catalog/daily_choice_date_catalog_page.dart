import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../app/navigation/ordinary_page_scaffold.dart';
import '../../domain/calendar_date.dart';
import 'daily_choice_catalog_body.dart';
import 'daily_choice_catalog_instance.dart';

@RoutePage()
final class DailyChoiceDateCatalogPage extends StatefulWidget {
  const DailyChoiceDateCatalogPage({required this.date, super.key});

  final CalendarDate date;

  @override
  State<DailyChoiceDateCatalogPage> createState() =>
      _DailyChoiceDateCatalogPageState();
}

final class _DailyChoiceDateCatalogPageState
    extends State<DailyChoiceDateCatalogPage> {
  late final DailyChoiceCatalogInstance _instance;

  @override
  void initState() {
    super.initState();
    _instance = DailyChoiceCatalogInstance(initialDate: widget.date);
  }

  @override
  Widget build(BuildContext context) => OrdinaryPageScaffold(
    appBar: AppBar(
      title: Text(AppLocalizations.of(context).appDestinationDailyChoices),
    ),
    body: DailyChoiceCatalogBody(
      key: ObjectKey(_instance),
      instance: _instance,
    ),
  );
}
