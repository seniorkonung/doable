import 'dart:async';

import 'package:doable/src/favorite/application/favorite_intentions.dart';
import 'package:doable/src/favorite/presentation/home/home_state.dart';
import 'package:doable/src/favorite/presentation/home/home_view_model.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Поднимает view model Главной над управляемым чтением избранного.
final class HomeHarness {
  /// [firstReadError] — исключение, которое граница бросает при запуске
  /// первоначального чтения.
  HomeHarness({Object? firstReadError}) {
    repository.nextReadError = firstReadError;
    container = ProviderContainer(
      overrides: [
        personalGraphRepositoryProvider.overrideWith((ref) => repository),
      ],
    );
    subscription = container.listen(homeViewModelProvider, (_, _) {});
  }

  final repository = HomeTestRepository();
  late final ProviderContainer container;
  late final ProviderSubscription<HomeState> subscription;

  HomeViewModel get model => container.read(homeViewModelProvider.notifier);
  HomeState get state => container.read(homeViewModelProvider);

  void dispose() {
    subscription.close();
    container.dispose();
  }
}

/// Управляемая реализация контракта чтения избранного: каждое чтение
/// завершается тестом явно и в выбранном им порядке.
final class HomeTestRepository extends Fake implements PersonalGraphRepository {
  final reads = <Completer<FavoriteIntentionsResult>>[];

  /// Исключение, которое граница бросает вместо следующего чтения.
  Object? nextReadError;

  int get readCount => reads.length;

  @override
  Future<FavoriteIntentionsResult> getFavoriteIntentions() {
    final completer = Completer<FavoriteIntentionsResult>();
    reads.add(completer);
    final error = nextReadError;
    if (error != null) {
      nextReadError = null;
      throw error;
    }
    return completer.future;
  }

  void completeRead(
    int index, {
    List<FavoriteIntentionRow> items = const [],
    int archivedCount = 0,
    int revision = 1,
  }) => reads[index].complete(
    FavoriteIntentionsSuccess(
      FavoriteIntentionsSnapshot(
        items: items,
        archivedCount: archivedCount,
        revision: HomeTestRevision(revision),
      ),
    ),
  );

  void failRead(int index, FavoriteIntentionsReadFailure failure) =>
      reads[index].complete(FavoriteIntentionsError(failure));

  void throwFromRead(int index, Object error) =>
      reads[index].completeError(error);
}

final class HomeTestRevision implements GraphRevision {
  const HomeTestRevision(this.number, [this.epoch = 0]);

  final int number;
  final int epoch;

  @override
  GraphRevisionOrder compareTo(GraphRevision other) => switch (other) {
    HomeTestRevision(epoch: final e) when e != epoch =>
      GraphRevisionOrder.differentEpoch,
    HomeTestRevision(number: final n) when number < n =>
      GraphRevisionOrder.older,
    HomeTestRevision(number: final n) when number > n =>
      GraphRevisionOrder.newer,
    HomeTestRevision() => GraphRevisionOrder.same,
    _ => GraphRevisionOrder.differentEpoch,
  };
}

IntentionId homeTestIntentionId(int number) => (IntentionId.decode(
  '018f0000-0000-7000-8000-${number.toRadixString(16).padLeft(12, '0')}',
) as IntentionIdDecodingSuccess).id;

FavoriteIntentionRow homeTestRow(
  int number,
  String title, {
  IntentionReadiness readiness = IntentionReadiness.notReady,
  int activeRelationCount = 0,
}) => FavoriteIntentionRow(
  id: homeTestIntentionId(number),
  title: title,
  readiness: readiness,
  activeRelationCount: activeRelationCount,
);
