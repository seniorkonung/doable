import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/app_localizations.dart';
import 'daily_choice_catalog_body.dart';
import 'daily_choice_catalog_instance.dart';
import 'daily_choice_local_date_provider.dart';

@RoutePage()
final class DailyChoiceCatalogPage extends ConsumerStatefulWidget {
  const DailyChoiceCatalogPage({super.key});

  @override
  ConsumerState<DailyChoiceCatalogPage> createState() =>
      _DailyChoiceCatalogPageState();
}

final class _DailyChoiceCatalogPageState
    extends ConsumerState<DailyChoiceCatalogPage> {
  /// Корневой каталог получает свой ключ при первом открытии в процессе.
  late final DailyChoiceCatalogInstance _instance;

  @override
  void initState() {
    super.initState();
    _instance = DailyChoiceCatalogInstance(
      initialDate: ref.read(dailyChoiceLocalDateSourceProvider)().date,
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(AppLocalizations.of(context).appDestinationDailyChoices),
    ),
    body: DailyChoiceCatalogBody(
      key: ObjectKey(_instance),
      instance: _instance,
    ),
  );
}
