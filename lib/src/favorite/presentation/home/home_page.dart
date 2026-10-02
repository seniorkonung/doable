import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../app/navigation/app_destination.dart';
import '../../../app/routing/app_router.gr.dart';
import '../../../intention/domain/intention.dart';
import '../../../intention/presentation/intention_summary_view.dart';
import '../../application/favorite_intentions.dart';
import 'home_state.dart';
import 'home_view_model.dart';

/// Главная — корневая страница со списком избранных намерений.
///
/// Отметка ставится и снимается только на странице намерения, поэтому
/// страница показывает список и открывает намерение, но не меняет избранное.
@RoutePage()
final class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    final state = ref.watch(homeViewModelProvider);
    final model = ref.read(homeViewModelProvider.notifier);
    return Scaffold(
      appBar: AppBar(title: Text(AppDestination.home.title(localizations))),
      body: SafeArea(
        child: switch (state) {
          HomeLoading() => _HomeStatus(
            message: localizations.homeLoading,
            progressIndicator: true,
          ),
          HomeUnavailable() => _HomeStatus(
            message: localizations.homeUnavailable,
            actionLabel: localizations.commonRetry,
            onAction: () => unawaited(model.retry()),
          ),
          // Повреждение и неизвестный отказ — отдельные неповторяемые
          // результаты: обычный повтор их не восстанавливает.
          HomeCorruption() => _HomeStatus(
            message: localizations.homeCorruption,
          ),
          HomeUnexpected() => _HomeStatus(
            message: localizations.homeUnexpected,
          ),
          final HomeLoaded loaded => _HomeLoadedView(
            loaded: loaded,
            onRetry: () => unawaited(model.retry()),
          ),
        },
      ),
    );
  }
}

/// Подтверждённый снимок избранного: пометка актуальности над списком либо
/// пустым состоянием.
final class _HomeLoadedView extends StatelessWidget {
  const _HomeLoadedView({required this.loaded, required this.onRetry});

  final HomeLoaded loaded;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return LayoutBuilder(
      builder: (context, constraints) => Column(
        children: [
          // Пометка занимает не больше двух третей высоты и стоит над
          // списком вне его прокрутки: под ней всегда остаются строки, а её
          // появление и исчезновение не сдвигают позицию списка. Место
          // пометки существует при любой актуальности, чтобы список не
          // пересоздавался.
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: constraints.maxHeight * 2 / 3,
            ),
            child: SingleChildScrollView(
              primary: false,
              child: _HomeFreshnessMark(
                freshness: loaded.freshness,
                onRetry: onRetry,
              ),
            ),
          ),
          Expanded(
            child: switch (loaded) {
              HomeList(:final items) => _HomeFavoriteList(items: items),
              HomeEmpty(:final reason) => _HomeStatus(
                message: switch (reason) {
                  HomeEmptyReason.noFavorites =>
                    localizations.homeEmptyNoFavorites,
                  HomeEmptyReason.allArchived =>
                    localizations.homeEmptyAllArchived,
                },
                actionLabel: localizations.homeOpenIntentionGraph,
                // Типизированный маршрут каталога: Главная не знает индексов
                // пунктов основной навигации.
                onAction: () => unawaited(
                  context.navigateTo(const IntentionCatalogRoute()),
                ),
              ),
            },
          ),
        ],
      ),
    );
  }
}

/// Пометка, что показанный снимок не обновлён, с повтором только при
/// недоступности. При текущей актуальности и во время обновления ничего не
/// выводит и не занимает места.
final class _HomeFreshnessMark extends StatelessWidget {
  const _HomeFreshnessMark({required this.freshness, required this.onRetry});

  final HomeFreshness freshness;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final stale = switch (freshness) {
      HomeFreshnessCurrent() || HomeFreshnessRefreshing() => null,
      final HomeFreshnessStale stale => stale,
    };
    if (stale == null) return const SizedBox.shrink();
    return Semantics(
      container: true,
      liveRegion: true,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(switch (stale.failure) {
              FavoriteIntentionsUnavailableFailure() =>
                localizations.homeRefreshUnavailable,
              FavoriteIntentionsCorruptionFailure() =>
                localizations.homeRefreshCorruption,
              FavoriteIntentionsUnexpectedFailure() =>
                localizations.homeRefreshUnexpected,
            }, textAlign: TextAlign.center),
            if (stale.canRetry) ...[
              const SizedBox(height: 12),
              FilledButton(
                onPressed: onRetry,
                child: Text(localizations.commonRetry),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Все активные избранные намерения одним списком в порядке снимка.
final class _HomeFavoriteList extends StatelessWidget {
  const _HomeFavoriteList({required this.items});

  final List<FavoriteIntentionRow> items;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return CustomScrollView(
      key: const PageStorageKey<String>('home-favorite-intentions'),
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Semantics(
              header: true,
              child: Text(
                localizations.homeFavoritesHeading,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ),
        ),
        SliverList.builder(
          itemCount: items.length,
          itemBuilder: (context, index) {
            final row = items[index];
            return HomeIntentionRow(
              key: ValueKey(row.id),
              row: row,
              // Страница открывается по идентификатору: одноимённые
              // намерения остаются разными строками.
              onTap: () => unawaited(
                context.router.push(IntentionDetailsRoute(intentionId: row.id)),
              ),
            );
          },
        ),
      ],
    );
  }
}

/// Строка избранного намерения на Главной.
///
/// Показывает название без изменения, готовность к действию и точное число
/// активных связей. Звезды, тегов, признака описания и архивного состояния
/// нет: все намерения списка — активные избранные.
final class HomeIntentionRow extends StatelessWidget {
  const HomeIntentionRow({required this.row, required this.onTap, super.key});

  final FavoriteIntentionRow row;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return IntentionSummaryView(
      title: row.title,
      archiveState: IntentionArchiveState.active,
      showArchiveState: false,
      traits: [
        switch (row.readiness) {
          IntentionReadiness.ready => localizations.catalogReady,
          IntentionReadiness.notReady => localizations.catalogNotReady,
        },
      ],
      activeRelationCount: ConfirmedActiveRelationCount(
        row.activeRelationCount,
      ),
      onTap: onTap,
    );
  }
}

/// Состояние Главной вместо списка: загрузка, пустое состояние или отказ.
///
/// Живая область сообщает об изменении экранному диктору, а содержимое
/// прокручивается, поэтому увеличенный текст не скрывает действие.
final class _HomeStatus extends StatelessWidget {
  const _HomeStatus({
    required this.message,
    this.progressIndicator = false,
    this.actionLabel,
    this.onAction,
  }) : assert(
         (actionLabel == null) == (onAction == null),
         'Действие требует и подписи, и обработчика.',
       );

  final String message;
  final bool progressIndicator;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Semantics(
            container: true,
            liveRegion: true,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (progressIndicator) ...[
                  const CircularProgressIndicator(),
                  const SizedBox(height: 24),
                ],
                Text(message, textAlign: TextAlign.center),
                if (onAction case final action?) ...[
                  const SizedBox(height: 24),
                  FilledButton(onPressed: action, child: Text(actionLabel!)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
