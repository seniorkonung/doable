import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../graph/application/graph_command_result.dart';
import '../../../graph/application/personal_graph_repository_provider.dart';
import '../../application/favorite_intentions.dart';
import 'home_state.dart';

part 'home_view_model.g.dart';

@riverpod
final class HomeViewModel extends _$HomeViewModel {
  late FavoriteReadContract _favorites;
  int _generation = 0;

  @override
  HomeState build() {
    _favorites = ref.watch(personalGraphRepositoryProvider);
    _generation++;
    unawaited(_load(_generation));
    return const HomeLoading();
  }

  /// Повтор доступен только при недоступности; при остальных состояниях
  /// чтение не запускается.
  Future<void> retry() {
    if (state is! HomeUnavailable) return Future.value();
    state = const HomeLoading();
    return _load(++_generation);
  }

  /// Ответ публикуется, только пока [generation] остаётся текущим: ответ
  /// прежнего чтения не заменяет состояние нового.
  Future<void> _load(int generation) async {
    final result = await _read();
    if (!ref.mounted || generation != _generation) return;
    state = switch (result) {
      GraphResultSuccess(:final value) => _loaded(value),
      GraphResultFailure(:final failure) => switch (failure) {
        FavoriteIntentionsUnavailableFailure() => const HomeUnavailable(),
        FavoriteIntentionsCorruptionFailure() => const HomeCorruption(),
        FavoriteIntentionsUnexpectedFailure() => const HomeUnexpected(),
      },
    };
  }

  Future<FavoriteIntentionsResult> _read() async {
    try {
      return await _favorites.getFavoriteIntentions();
    } on Object {
      return const FavoriteIntentionsError(
        FavoriteIntentionsUnexpectedFailure(),
      );
    }
  }

  HomeLoaded _loaded(FavoriteIntentionsSnapshot snapshot) {
    if (snapshot.items.isNotEmpty) {
      return HomeList(items: snapshot.items, revision: snapshot.revision);
    }
    return HomeEmpty(
      reason: snapshot.archivedCount == 0
          ? HomeEmptyReason.noFavorites
          : HomeEmptyReason.allArchived,
      revision: snapshot.revision,
    );
  }
}
