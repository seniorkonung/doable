import 'dart:convert';

import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/app/routing/app_router.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/tag/presentation/catalog/tag_catalog_state.dart';
import 'package:doable/src/tag/presentation/catalog/tag_catalog_view_model.dart';
import 'package:flutter/foundation.dart' show debugPrintSynchronously;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/graph/data/drift_tag_catalog_read_cost_test.dart' as cost;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('стоимость каталога тегов на устройстве', (tester) async {
    await cost.measureTagCatalogReadCost(
      onCatalogReady: (repository) => _measureCatalogScroll(tester, repository),
    );
  });
}

Future<void> _measureCatalogScroll(
  WidgetTester tester,
  DriftPersonalGraphRepository repository,
) async {
  final router = AppRouter();
  try {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          personalGraphRepositoryProvider.overrideWithValue(repository),
        ],
        child: MaterialApp.router(
          locale: const Locale('ru'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router.config(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('catalog-open-tags')));
    await tester.pumpAndSettle();
    final list = find.byKey(const ValueKey('tag-catalog-list'));
    expect(list, findsOneWidget);

    final container = ProviderScope.containerOf(tester.element(list));
    final model = container.read(tagCatalogViewModelProvider.notifier);
    for (var page = 0; page < 10; page++) {
      expect(
        find.byKey(const ValueKey('tag-catalog-load-more')),
        findsOneWidget,
      );
      await tester.runAsync(model.loadMore);
      await tester.pumpAndSettle();
    }
    final loaded = container.read(tagCatalogViewModelProvider);
    expect(loaded, isA<TagCatalogLoaded>());
    final loadedCatalog = loaded as TagCatalogLoaded;
    expect(loadedCatalog.items, hasLength(550));

    final timings = <FrameTiming>[];
    void collect(List<FrameTiming> frames) => timings.addAll(frames);
    SchedulerBinding.instance.addTimingsCallback(collect);
    try {
      for (var movement = 0; movement < 20; movement++) {
        await tester.fling(list, Offset(0, movement < 10 ? -600 : 600), 1200);
        await tester.pumpAndSettle();
      }
      await tester.pump(const Duration(milliseconds: 100));
    } finally {
      SchedulerBinding.instance.removeTimingsCallback(collect);
    }
    expect(timings, isNotEmpty);
    final frameMicros = [
      for (final frame in timings) frame.totalSpan.inMicroseconds,
    ]..sort();
    int percentile(double fraction) =>
        frameMicros[((frameMicros.length - 1) * fraction).round()];
    debugPrintSynchronously(
      jsonEncode({
        'kind': 'tag_catalog_scroll',
        'loadedRows': loadedCatalog.items.length,
        'gestures': 20,
        'frames': frameMicros.length,
        'p50Microseconds': percentile(0.50),
        'p95Microseconds': percentile(0.95),
        'maxMicroseconds': frameMicros.last,
        'framesOver16667Microseconds': frameMicros
            .where((duration) => duration > 16667)
            .length,
        'framesOver33333Microseconds': frameMicros
            .where((duration) => duration > 33333)
            .length,
      }),
    );
  } finally {
    await tester.pumpWidget(const SizedBox.shrink());
    router.dispose();
  }
}
