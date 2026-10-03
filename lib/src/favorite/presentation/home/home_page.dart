import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../app/navigation/app_destination.dart';
import '../../../app/routing/app_router.gr.dart';
import '../../../intention/domain/intention.dart';
import '../../../intention/domain/intention_id.dart';
import '../../../intention/presentation/intention_summary_view.dart';
import '../../application/favorite_intentions.dart';
import '../../domain/favorite_order.dart';
import 'home_state.dart';
import 'home_view_model.dart';

/// Главная — корневая страница со списком избранных намерений.
///
/// Отметка ставится и снимается только на странице намерения, поэтому
/// страница показывает список, открывает намерение и меняет только порядок
/// избранных намерений.
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
            onMove: model.move,
          ),
        },
      ),
    );
  }
}

/// Подтверждённый снимок избранного: пометка актуальности над списком либо
/// пустым состоянием.
final class _HomeLoadedView extends StatelessWidget {
  const _HomeLoadedView({
    required this.loaded,
    required this.onRetry,
    required this.onMove,
  });

  final HomeLoaded loaded;
  final VoidCallback onRetry;
  final _HomeMoveCallback onMove;

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
              final HomeList list => _HomeFavoriteList(
                list: list,
                onMove: onMove,
              ),
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

typedef _HomeMoveCallback = void Function(
  IntentionId intentionId,
  FavoritePlacement placement,
);

/// Все активные избранные намерения одним списком в показанном порядке.
///
/// Строки переставляются только ручкой, пока список принимает перестановку.
/// Тогда строки идут через [SliverReorderableList], который сам предлагает
/// экранному диктору перемещение строк. В остальное время — при записи,
/// ожидании актуального снимка, обновлении и неактуальности — тот же список
/// строится обычным [SliverList]: встроенных действий перемещения нет, а
/// прокрутка остаётся прежней, потому что меняется только содержимое
/// [CustomScrollView]. По той же причине список не использует
/// `ReorderableListView`: он всегда добавляет встроенные действия.
final class _HomeFavoriteList extends StatelessWidget {
  const _HomeFavoriteList({required this.list, required this.onMove});

  final HomeList list;
  final _HomeMoveCallback onMove;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final items = list.displayedItems;
    final savingId = switch (list.reorder) {
      HomeReorderPending(:final intentionId) => intentionId,
      HomeReorderIdle() => null,
    };
    Widget row(int index, HomeRowReorder reorder) {
      final row = items[index];
      return HomeIntentionRow(
        key: ValueKey(row.id),
        row: row,
        reorder: reorder,
        // Страница открывается по идентификатору: одноимённые намерения
        // остаются разными строками.
        onTap: () => unawaited(
          context.router.push(IntentionDetailsRoute(intentionId: row.id)),
        ),
      );
    }

    final scrollView = CustomScrollView(
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
        if (list.acceptsReorder)
          SliverReorderableList(
            itemCount: items.length,
            itemBuilder: (context, index) => row(index, HomeRowMovable(index)),
            onReorderItem: (from, to) => _move(items, from, to),
            proxyDecorator: _raiseDraggedRow,
          )
        else
          SliverList.builder(
            itemCount: items.length,
            itemBuilder: (context, index) => row(
              index,
              items[index].id == savingId
                  ? const HomeRowSaving()
                  : const HomeRowImmovable(),
            ),
          ),
      ],
    );
    return Stack(
      fit: StackFit.expand,
      children: [
        // Живая область лежит под списком: касания и исследование касанием
        // достаются строкам.
        _HomeMoveAnnouncement(confirmedMove: list.confirmedMove),
        scrollView,
      ],
    );
  }

  /// Переводит перемещение строки с места [from] на место [to] показанного
  /// списка [items] в перемещение по идентификаторам: намерение встаёт сразу
  /// после строки, которая оказалась перед ним, а на первом месте — первым во
  /// всём порядке. [to] — место строки в списке после перемещения.
  void _move(List<FavoriteIntentionRow> items, int from, int to) {
    final moved = items[from];
    final rest = [...items]..removeAt(from);
    onMove(
      moved.id,
      to == 0
          ? const FirstFavoritePlacement()
          : AfterFavoritePlacement(rest[to - 1].id),
    );
  }

  /// Перетаскиваемая копия строки рисуется поверх страницы, вне её
  /// материала, поэтому получает собственный материал с тенью.
  static Widget _raiseDraggedRow(
    Widget child,
    int index,
    Animation<double> animation,
  ) => AnimatedBuilder(
    animation: animation,
    builder: (context, child) => Material(
      elevation: 6 * Curves.easeInOut.transform(animation.value),
      child: child,
    ),
    child: child,
  );
}

/// Живая область, которая объявляет экранному диктору новое место намерения
/// после подтверждения перестановки цельным снимком.
///
/// На экране она ничего не показывает: успешную перестановку человек видит
/// по новому порядку списка. Объявление длится столько же, сколько общее
/// сообщение по умолчанию, и затем убирается: иначе экранный диктор
/// повторял бы прежний результат при каждом возвращении на Главную. Каждое
/// подтверждение получает новый узел, поэтому тот же текст звучит заново.
final class _HomeMoveAnnouncement extends StatefulWidget {
  const _HomeMoveAnnouncement({required this.confirmedMove});

  final HomeConfirmedMove? confirmedMove;

  @override
  State<_HomeMoveAnnouncement> createState() => _HomeMoveAnnouncementState();
}

final class _HomeMoveAnnouncementState extends State<_HomeMoveAnnouncement> {
  static const _duration = Duration(seconds: 4);

  /// Последнее полученное подтверждение: копии снимка несут тот же объект и
  /// заново не объявляются.
  HomeConfirmedMove? _received;
  HomeConfirmedMove? _announced;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _receive(widget.confirmedMove);
  }

  @override
  void didUpdateWidget(_HomeMoveAnnouncement oldWidget) {
    super.didUpdateWidget(oldWidget);
    _receive(widget.confirmedMove);
  }

  void _receive(HomeConfirmedMove? confirmedMove) {
    if (confirmedMove == null || identical(confirmedMove, _received)) return;
    _received = confirmedMove;
    _announced = confirmedMove;
    _timer?.cancel();
    _timer = Timer(_duration, () => setState(() => _announced = null));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final announced = _announced;
    if (announced == null) return const SizedBox.shrink();
    return Semantics(
      key: ObjectKey(announced),
      container: true,
      liveRegion: true,
      label: AppLocalizations.of(context).homeReorderMoved(
        announced.row.title,
        announced.position,
        announced.count,
      ),
      // Узел без площади экранный диктор не получает.
      child: const SizedBox.expand(),
    );
  }
}

/// Участие строки Главной в перестановке.
sealed class HomeRowReorder {
  const HomeRowReorder();
}

/// Список принимает перестановку: ручка начинает перетаскивание строки на
/// месте [index] показанного списка.
final class HomeRowMovable extends HomeRowReorder {
  const HomeRowMovable(this.index);

  final int index;
}

/// Список сейчас не принимает перестановку: ручка недоступна.
final class HomeRowImmovable extends HomeRowReorder {
  const HomeRowImmovable();
}

/// Запрошенное новое место намерения ещё не подтверждено: строка показывает
/// его сохранение, а ручка недоступна.
final class HomeRowSaving extends HomeRowReorder {
  const HomeRowSaving();
}

/// Строка избранного намерения на Главной.
///
/// Показывает название без изменения, готовность к действию, точное число
/// активных связей и ручку перемещения в конце строки. Звезды, тегов,
/// признака описания и архивного состояния нет: все намерения списка —
/// активные избранные. Нажатие строки открывает намерение, а перетаскивание
/// начинается только с ручки: долгое нажатие строки его не начинает.
final class HomeIntentionRow extends StatelessWidget {
  const HomeIntentionRow({
    required this.row,
    required this.reorder,
    required this.onTap,
    super.key,
  });

  final FavoriteIntentionRow row;
  final HomeRowReorder reorder;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    // Ручка своего узла семантики не создаёт: строку экранному диктору
    // объявляет одним узлом её представление намерения.
    final content = Row(
      children: [
        Expanded(
          child: IntentionSummaryView(
            title: row.title,
            archiveState: IntentionArchiveState.active,
            showArchiveState: false,
            semanticsNode: IntentionSummarySemanticsNode.enclosing,
            traits: [
              switch (row.readiness) {
                IntentionReadiness.ready => localizations.catalogReady,
                IntentionReadiness.notReady => localizations.catalogNotReady,
              },
              // Пока новое место не подтверждено, строка не выдаёт его за
              // сохранённое.
              if (reorder case HomeRowSaving()) localizations.homeReorderSaving,
            ],
            activeRelationCount: ConfirmedActiveRelationCount(
              row.activeRelationCount,
            ),
            onTap: onTap,
          ),
        ),
        Padding(
          padding: const EdgeInsetsDirectional.only(end: 8),
          child: _HomeReorderHandle(reorder: reorder),
        ),
      ],
    );
    return switch (reorder) {
      // Узел строки создаёт сам переставляемый список вместе с системными
      // действиями перемещения, и строка дополняет его: экранный диктор
      // получает название, подписи, переход и перемещение одним узлом.
      HomeRowMovable() => content,
      HomeRowImmovable() || HomeRowSaving() => MergeSemantics(child: content),
    };
  }
}

/// Ручка перемещения строки Главной.
///
/// Экранному диктору она не видна: перемещение ему предлагает сам список
/// встроенными действиями.
final class _HomeReorderHandle extends StatelessWidget {
  const _HomeReorderHandle({required this.reorder});

  final HomeRowReorder reorder;

  @override
  Widget build(BuildContext context) {
    final handle = SizedBox.square(
      dimension: 48,
      child: Icon(
        Icons.drag_handle,
        color: switch (reorder) {
          HomeRowMovable() => null,
          HomeRowImmovable() ||
          HomeRowSaving() => Theme.of(context).disabledColor,
        },
      ),
    );
    return switch (reorder) {
      HomeRowMovable(:final index) => Tooltip(
        message: AppLocalizations.of(context).homeReorderHandleTooltip,
        excludeFromSemantics: true,
        child: ReorderableDragStartListener(index: index, child: handle),
      ),
      HomeRowImmovable() || HomeRowSaving() => handle,
    };
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
