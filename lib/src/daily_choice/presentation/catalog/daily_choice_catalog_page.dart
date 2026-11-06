import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../design_system/components/scroll_top_button.dart';
import '../../../shared/presentation/local_day/local_date_provider.dart';
import 'daily_choice_catalog_body.dart';
import 'daily_choice_catalog_instance.dart';

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
      initialDate: ref.read(localDateSourceProvider)().date,
    );
  }

  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
    // Без AppBar стиль системной строки задаёт страница:
    // https://api.flutter.dev/flutter/services/SystemChrome/setSystemUIOverlayStyle.html
    value: Theme.of(context).brightness == Brightness.dark
        ? SystemUiOverlayStyle.light
        : SystemUiOverlayStyle.dark,
    child: DailyChoiceCatalogBody(
      key: ObjectKey(_instance),
      instance: _instance,
      scaffoldBuilder: (body, scrollTopButton) => Scaffold(
        body: body,
        floatingActionButton: scrollTopButton,
        floatingActionButtonLocation: const ScrollTopButtonLocation(),
      ),
    ),
  );
}
