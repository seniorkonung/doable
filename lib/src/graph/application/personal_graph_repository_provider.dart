import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../intention/application/intention_command.dart';
import '../../intention/application/intention_repository.dart';
import '../../intention/application/intention_result.dart';
import '../../intention/presentation/operation/intention_repository_provider.dart';
import 'graph_revision.dart';
import 'personal_graph_repository.dart';

part 'personal_graph_repository_provider.g.dart';

@Riverpod(keepAlive: true)
GraphCommandRepository personalGraphRepository(Ref ref) =>
    _IntentionRepositoryCommandCompatibility(
      ref.watch(intentionRepositoryProvider),
    );

final class _IntentionRepositoryCommandCompatibility
    implements GraphCommandRepository {
  _IntentionRepositoryCommandCompatibility(this._repository);

  final IntentionRepository _repository;

  @override
  Future<Result<ConfirmedGraphResult<IntentionCommandSuccess>>> execute(
    IntentionCommand command,
  ) async {
    final result = await _repository.execute(command);
    return switch (result) {
      ResultSuccess(:final value) => () {
        final revision = value.catalogMutation.revision;
        return ResultSuccess(
          ConfirmedGraphResult(revision: revision, value: value),
        );
      }(),
      ResultFailure(:final failure) => ResultFailure(failure),
    };
  }
}
