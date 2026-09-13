import '../../data/local/app_database.dart' hide Intention;
import '../../graph/application/graph_revision.dart';
import '../../graph/application/personal_graph_repository.dart';
import '../../graph/data/drift_personal_graph_repository.dart';
import '../../shared/diagnostics/diagnostics_sink.dart';
import '../application/intention_command.dart';
import '../application/intention_id_generator.dart';
import '../application/intention_repository.dart';
import '../application/intention_result.dart';
import '../domain/intention.dart';
import '../domain/intention_id.dart';

@Deprecated('Используйте DriftPersonalGraphRepository.')
final class DriftIntentionRepository implements IntentionRepository {
  DriftIntentionRepository(
    AppDatabase database,
    IntentionIdGenerator idGenerator,
    DateTime Function() now,
    DiagnosticsSink diagnosticsSink,
  ) : this.fromPersonalGraphRepository(
        DriftPersonalGraphRepository(
          database,
          idGenerator,
          now,
          diagnosticsSink,
        ),
      );

  DriftIntentionRepository.fromPersonalGraphRepository(this._delegate);

  final PersonalGraphRepository _delegate;

  @override
  Future<Result<IntentionCatalogPage>> getCatalogPage(
    IntentionCatalogQuery query,
  ) => _delegate.getCatalogPage(query);

  @override
  Stream<Result<Intention?>> watchById(IntentionId id) async* {
    await for (final result in _delegate.watchIntention(id)) {
      yield switch (result) {
        ResultSuccess<GraphSnapshot<Intention?>>(:final value) => ResultSuccess(
          value.value,
        ),
        ResultFailure<GraphSnapshot<Intention?>>(:final failure) =>
          ResultFailure(failure),
      };
    }
  }

  @override
  Future<Result<IntentionCommandSuccess>> execute(
    IntentionCommand command,
  ) async => switch (await _delegate.execute(command)) {
    ResultSuccess<ConfirmedGraphResult<IntentionCommandSuccess>>(
      :final value,
    ) =>
      ResultSuccess(value.value),
    ResultFailure<ConfirmedGraphResult<IntentionCommandSuccess>>(
      :final failure,
    ) =>
      ResultFailure(failure),
  };
}
