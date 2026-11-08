import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/navigation/graph_generation.dart';
import '../../../design_system/components/scroll_top_button.dart';
import '../../../shared/presentation/local_day/local_date_provider.dart';
import 'action_day_body.dart';
import 'action_day_instance.dart';

/// Экземпляр корневого экрана доступен его панели вне дерева вкладки.
final actionDayRootInstanceProvider = Provider<ActionDayInstance>((ref) {
  ref.watch(currentGraphGenerationProvider);
  return ActionDayInstance(
    initialDate: ref.read(localDateSourceProvider)().date,
  );
});

@RoutePage()
final class ActionDayRootPage extends ConsumerStatefulWidget {
  const ActionDayRootPage({super.key});

  @override
  ConsumerState<ActionDayRootPage> createState() => _ActionDayRootPageState();
}

final class _ActionDayRootPageState extends ConsumerState<ActionDayRootPage> {
  /// Корневой экран дня получает свой ключ при первом открытии в процессе.
  late final ActionDayInstance _instance;

  @override
  void initState() {
    super.initState();
    _instance = ref.read(actionDayRootInstanceProvider);
  }

  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
    // Без AppBar стиль системной строки задаёт страница:
    // https://api.flutter.dev/flutter/services/SystemChrome/setSystemUIOverlayStyle.html
    value: Theme.of(context).brightness == Brightness.dark
        ? SystemUiOverlayStyle.light
        : SystemUiOverlayStyle.dark,
    child: ActionDayBody(
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
