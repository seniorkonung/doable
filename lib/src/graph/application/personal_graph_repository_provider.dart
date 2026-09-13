import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../intention/application/intention_command.dart';
import '../../intention/application/intention_repository.dart';
import '../../intention/application/intention_result.dart';
import '../../intention/domain/intention.dart';
import '../../intention/domain/intention_id.dart';
import '../../intention/presentation/operation/intention_repository_provider.dart';
import 'graph_revision.dart';
import 'personal_graph_repository.dart';

part 'personal_graph_repository_provider.g.dart';

@Riverpod(keepAlive: true)
PersonalGraphRepository personalGraphRepository(Ref ref) =>
    _IntentionRepositoryCompatibility(ref.watch(intentionRepositoryProvider));

final class _IntentionRepositoryCompatibility
    implements PersonalGraphRepository {
  _IntentionRepositoryCompatibility(this._repository);

  final IntentionRepository _repository;

  @override
  Future<Result<IntentionCatalogPage>> getCatalogPage(
    IntentionCatalogQuery query,
  ) => _repository.getCatalogPage(query);

  @override
  Stream<Result<GraphSnapshot<Intention?>>> watchIntention(IntentionId id) =>
      throw UnsupportedError(
        'Совместимый вход не предоставляет ревизию подробного снимка.',
      );

  @override
  Future<Result<ConfirmedGraphResult<IntentionCommandSuccess>>> execute(
    IntentionCommand command,
  ) async {
    final result = await _repository.execute(command);
    return switch (result) {
      ResultSuccess(:final value) => ResultSuccess(
        ConfirmedGraphResult(
          revision: value.catalogMutation.revision,
          value: value,
        ),
      ),
      ResultFailure(:final failure) => ResultFailure(failure),
    };
  }
}
