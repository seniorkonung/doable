import 'dart:async';

import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/app/localization/app_locale_resolution.dart';
import 'package:doable/src/app/routing/app_router.dart';
import 'package:doable/src/daily_choice/application/daily_choice_catalog.dart';
import 'package:doable/src/daily_choice/application/daily_choice_details.dart';
import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_id.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/app_root_pages.dart';
import '../../../support/catalog_reconciliation_test_fallback.dart';
import '../../../support/daily_choice_local_date.dart';
import '../../../support/favorite_read_contract_test_fallback.dart';
import '../../../support/tag_read_contract_test_fallback.dart';
import '../../../support/in_memory_quick_creation_mode_store.dart';

/// Открывает каталог дневных выборов в оболочке приложения, как его видит
/// человек: с панелью основной навигации и общей кнопкой быстрого создания.
///
/// Приложение собрано с делегатами локализации и правилами выбора локали
/// приложения, поэтому [locale] — системная локаль устройства, а
/// неподдерживаемый язык даёт английский. [textScale] — системный размер
/// текста, [size] — логический размер экрана; [today] — локальное сегодня.
/// Чтения каталога завершает сценарий через [repository].
Future<void> pumpCatalogPage(
  WidgetTester tester,
  CatalogPageRepository repository, {
  required CalendarDate today,
  required Locale locale,
  required Size size,
  double textScale = 1,
}) async {
  tester.platformDispatcher.localesTestValue = [locale];
  addTearDown(tester.platformDispatcher.clearLocalesTestValue);
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final router = AppRouter();
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        inMemoryQuickCreationModeOverride,
        personalGraphRepositoryProvider.overrideWithValue(repository),
        ControlledDailyChoiceLocalDate(today).override,
      ],
      retry: (count, error) => null,
      child: MaterialApp.router(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        localeListResolutionCallback: resolveAppLocale,
        routerConfig: router.config(),
      ),
    ),
  );
  openDailyChoicesOn(router);
  await tester.pump();
  // Переход к каталогу заканчивается без анимации, а первое чтение каталога
  // остаётся незавершённым до решения сценария.
  await tester.pump(const Duration(milliseconds: 400));
}

/// Хранилище личного графа для страничных проверок каталога дневных выборов.
///
/// Записывает каждый запрос каталога в [queries] и оставляет его ответ
/// незавершённым, пока сценарий не завершит его успехом или отказом по номеру
/// запроса.
final class CatalogPageRepository
    with
        TagReadContractTestFallback,
        FavoriteReadContractTestFallback,
        CatalogReconciliationTestFallback
    implements PersonalGraphRepository {
  final queries = <DailyChoiceCatalogQuery>[];
  final _requests = <Completer<DailyChoiceCatalogPageResult>>[];

  @override
  Future<DailyChoiceCatalogPageResult> getDailyChoiceCatalogPage(
    DailyChoiceCatalogQuery query,
  ) {
    queries.add(query);
    final request = Completer<DailyChoiceCatalogPageResult>();
    _requests.add(request);
    return request.future;
  }

  /// Завершает запрос первой порции номер [index] строками [items] из
  /// [total] записей; [cursor] — продолжение выдачи.
  void completeFirst(
    int index,
    List<DailyChoiceCatalogItem> items, {
    required int total,
    DailyChoiceCatalogCursor? cursor,
  }) => _requests[index].complete(
    DailyChoiceCatalogPageSuccess(
      DailyChoiceCatalogFirstPage(
        items: items,
        totalCount: total,
        nextCursor: cursor,
        revision: const _Revision(),
      ),
    ),
  );

  /// Завершает запрос продолжения номер [index] последними строками [items].
  void completeMore(int index, List<DailyChoiceCatalogItem> items) =>
      _requests[index].complete(
        DailyChoiceCatalogPageSuccess(
          DailyChoiceCatalogContinuationPage(
            items: items,
            nextCursor: null,
            revision: const _Revision(),
          ),
        ),
      );

  /// Завершает запрос номер [index] доказанно временной недоступностью
  /// хранилища: каталог предлагает повтор.
  void failUnavailable(int index) => _requests[index].complete(
    const DailyChoiceCatalogPageError(DailyChoiceCatalogUnavailableFailure()),
  );

  @override
  Future<Result<IntentionCatalogPage>> getCatalogPage(
    IntentionCatalogQuery query,
  ) async => ResultSuccess(
    IntentionCatalogFirstPage(
      items: const [],
      totalCount: 0,
      nextCursor: null,
      revision: const _Revision(),
    ),
  );

  @override
  Stream<DailyChoiceReadResult> watchDailyChoice(DailyChoiceId id) =>
      const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Продолжение выдачи каталога после завершённой первой порции.
final class CatalogPageCursor implements DailyChoiceCatalogCursor {
  const CatalogPageCursor();
}

/// Дневной выбор номер [number] на дату [date]: «Чтобы Основание, я сегодня
/// Действие», не выполнен.
DailyChoiceCatalogItem catalogPageItem(
  int number, {
  required CalendarDate date,
}) => DailyChoiceCatalogItem(
  id: (DailyChoiceId.decode(_uuid(number)) as DailyChoiceIdDecodingSuccess).id,
  source: DailyChoiceCatalogParticipant(
    id: (IntentionId.decode(_uuid(1)) as IntentionIdDecodingSuccess).id,
    title: 'Основание',
    archiveState: IntentionArchiveState.active,
    readiness: IntentionReadiness.notReady,
  ),
  selected: DailyChoiceCatalogParticipant(
    id: (IntentionId.decode(_uuid(2)) as IntentionIdDecodingSuccess).id,
    title: 'Действие',
    archiveState: IntentionArchiveState.active,
    readiness: IntentionReadiness.ready,
  ),
  date: date,
  isCompleted: false,
);

String _uuid(int number) =>
    '00000000-0000-4000-8000-${number.toString().padLeft(12, '0')}';

final class _Revision implements GraphRevision {
  const _Revision();

  @override
  GraphRevisionOrder compareTo(GraphRevision other) => GraphRevisionOrder.same;
}
