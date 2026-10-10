import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_purpose.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_state.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_status_views.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_view_model.dart';
import 'package:doable/src/tag/application/tag_command.dart';
import 'package:doable/src/tag/domain/tag.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'catalog_reconciliation_test_support.dart';
import 'catalog_test_support.dart';

const _purpose = BrowseIntentionCatalog();

const _unavailableRu =
    'Список намерений не обновлён: не удалось получить изменения.';
const _corruptionRu =
    'Список намерений не обновлён: сохранённые данные повреждены.';
const _unexpectedRu =
    'Список намерений не обновлён из-за непредвиденной ошибки.';

final _view = find.byType(IntentionCatalogRefreshStatusView);
final _list = find.byKey(const ValueKey('refresh-status-test-list'));
final _retry = find.descendant(of: _view, matching: find.byType(FilledButton));

void main() {
  testWidgets(
    '«Повторить» вызывает retryRefresh модели назначения и не меняет список и позицию просмотра',
    (tester) async {
      final h = await _open(tester);
      final items = [
        for (var index = 40; index >= 1; index--) testSummary(index: index),
      ];
      await h.loadExcluding(items);
      await h.failRefresh(const ResultFailure(IntentionUnavailableFailure()));
      final scrollable = tester.state<ScrollableState>(
        find.descendant(of: _list, matching: find.byType(Scrollable)),
      );
      scrollable.position.jumpTo(300);
      await _settle(tester);
      final before = h.confirmed;
      expect(h.repository.reconciliationQueries, hasLength(1));

      await tester.tap(_retry);
      await _settle(tester);

      // Повтор запускает то же чтение области с прежними условиями.
      expect(h.repository.reconciliationQueries, hasLength(2));
      expect(
        h.repository.reconciliationQueryAt(1).catalogQuery.tagFilter,
        before.query.tagFilter,
      );
      expect(scrollable.position.pixels, 300);
      expect((h.confirmed as IntentionCatalogLoaded).items, items);
      // На время повторного чтения отказ не показывается.
      expect(find.text(_unavailableRu), findsNothing);

      h.repository.completeReconciliation(
        1,
        const ResultFailure(IntentionUnavailableFailure()),
      );
      await _settle(tester);
      expect(find.text(_unavailableRu), findsOneWidget);
      expect(scrollable.position.pixels, 300);

      // Успешный повтор снимает отказ.
      await tester.tap(_retry);
      await _settle(tester);
      h.repository.completeReconciliation(
        2,
        reconciliationFirstPortion(const [], totalCount: 40, revision: 2),
      );
      await _settle(tester);
      expect(h.confirmed.refresh, isA<IntentionCatalogRefreshIdle>());
      expect(find.text(_unavailableRu), findsNothing);
      expect(_retry, findsNothing);
      expect(scrollable.position.pixels, 300);
    },
  );

  // Живую область задаёт общее представление сообщения всех категорий
  // отказа; категория с повтором проверяет и кнопку.
  testWidgets('отказ обновления из-за недоступности объявляется живой '
      'областью', (tester) async {
    final semantics = tester.ensureSemantics();
    final h = await _open(tester);
    await h.loadExcluding([testSummary(index: 1)]);

    await h.failRefresh(const ResultFailure(IntentionUnavailableFailure()));

    final message = tester.getSemantics(find.text(_unavailableRu));
    expect(message.label, contains(_unavailableRu));
    expect(message.flagsCollection.isLiveRegion, isTrue);
    final retry = tester.getSemantics(_retry);
    expect(retry.label, 'Повторить');
    expect(retry.flagsCollection.isButton, isTrue);
    semantics.dispose();
  });

  for (final (language, retry, messages) in [
    ('ru', 'Повторить', [_unavailableRu, _corruptionRu, _unexpectedRu]),
    (
      'en',
      'Try again',
      [
        'The intention list isn’t up to date: changes couldn’t be loaded.',
        'The intention list isn’t up to date: stored data is damaged.',
        'The intention list isn’t up to date because of an unexpected error.',
      ],
    ),
  ]) {
    testWidgets('сообщения отказа обновления локализованы: $language', (
      tester,
    ) async {
      const states = <IntentionCatalogRefreshState>[
        IntentionCatalogRefreshUnavailable(),
        IntentionCatalogRefreshCorruption(),
        IntentionCatalogRefreshUnexpected(),
      ];
      for (final (index, refresh) in states.indexed) {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              personalGraphRepositoryProvider.overrideWithValue(
                ControlledCatalogRepository(),
              ),
            ],
            child: MaterialApp(
              locale: Locale(language),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: Scaffold(
                body: IntentionCatalogRefreshStatusView(
                  purpose: _purpose,
                  refresh: refresh,
                ),
              ),
            ),
          ),
        );

        expect(find.text(messages[index]), findsOneWidget);
        expect(
          find.descendant(of: _retry, matching: find.text(retry)),
          index == 0 ? findsOneWidget : findsNothing,
        );
      }
    });
  }
}

final _excluded = Tag(id: _tagId(1), name: TagName.fromInput('Спорт'));

TagId _tagId(int index) => switch (TagId.decode(
  '00000000-0000-4000-8000-${index.toString().padLeft(12, '0')}',
)) {
  TagIdDecodingSuccess(:final id) => id,
  InvalidTagIdDecoding() => throw StateError(
    'Некорректный идентификатор тега в тесте.',
  ),
};

/// Страница-образец: общее представление состояния обновления стоит над
/// сохранённой выдачей настоящей модели назначения.
final class _Host extends ConsumerWidget {
  const _Host();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(intentionCatalogViewModelProvider(_purpose)).value;
    if (state is! IntentionCatalogConfirmedState) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        IntentionCatalogRefreshStatusView(
          purpose: _purpose,
          refresh: state.refresh,
        ),
        Expanded(
          child: switch (state) {
            IntentionCatalogLoaded(:final items) => ListView(
              key: const ValueKey('refresh-status-test-list'),
              children: [
                for (final (index, item) in items.indexed)
                  SizedBox(
                    height: 48,
                    child: Text('${item.title} ${items.length - index}'),
                  ),
              ],
            ),
            IntentionCatalogEmpty() => IntentionCatalogStatusView(
              message: AppLocalizations.of(context).catalogActiveEmpty,
            ),
          },
        ),
      ],
    );
  }
}

final class _Harness {
  _Harness(this._tester, this.repository);

  final WidgetTester _tester;
  final ControlledCatalogRepository repository;
  int _revision = 1;

  ProviderContainer get _container =>
      ProviderScope.containerOf(_tester.element(find.byType(_Host)));

  IntentionCatalogConfirmedState get confirmed =>
      _container.read(intentionCatalogViewModelProvider(_purpose)).requireValue
          as IntentionCatalogConfirmedState;

  /// Загружает выдачу с исключённым тегом: его удаление требует чтения
  /// недостающей части, отказ которого и есть отказ обновления.
  Future<void> loadExcluding(List<IntentionSummary> items) async {
    final notifier = _container.read(
      intentionCatalogViewModelProvider(_purpose).notifier,
    );
    await _settle(_tester);
    final first = repository.queries.length - 1;
    repository.complete(
      first,
      ResultSuccess(
        IntentionCatalogFirstPage(
          items: const [],
          totalCount: 0,
          nextCursor: null,
          revision: TestCatalogRevision(_revision),
        ),
      ),
    );
    await _settle(_tester);
    notifier.changeTagFilter(
      IntentionTagFilter(excludedTagIds: [_excluded.id]),
    );
    await _settle(_tester);
    expect(repository.queries, hasLength(first + 2));
    repository.complete(
      first + 1,
      ResultSuccess(
        IntentionCatalogFirstPage(
          items: items,
          totalCount: items.length,
          nextCursor: null,
          revision: TestCatalogRevision(_revision),
        ),
      ),
    );
    await _settle(_tester);
  }

  /// Подтверждает удаление исключённого тега и завершает чтение
  /// согласования заданным отказом.
  Future<void> failRefresh(
    Result<IntentionCatalogReconciliationOutcome> failure,
  ) async {
    final read = repository.reconciliationQueries.length;
    _revision++;
    acceptTagCommand(
      _container,
      repository,
      DeleteTag(_excluded.id),
      tagDeletionSuccess(
        tagId: _excluded.id,
        revision: TestCatalogRevision(_revision),
      ),
    );
    await _settle(_tester);
    expect(repository.reconciliationQueries, hasLength(read + 1));
    repository.completeReconciliation(read, failure);
    await _settle(_tester);
  }
}

Future<_Harness> _open(WidgetTester tester) async {
  final repository = ControlledCatalogRepository();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        personalGraphRepositoryProvider.overrideWithValue(repository),
      ],
      retry: (retryCount, error) => null,
      child: MaterialApp(
        locale: const Locale('ru'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: _Host()),
      ),
    ),
  );
  return _Harness(tester, repository);
}

/// Завершённое чтение публикует состояние в микрозадаче, а перестроение
/// приходит следующим кадром.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
}
