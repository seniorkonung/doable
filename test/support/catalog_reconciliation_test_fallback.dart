import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_result.dart';

/// Подставляет отказ чтения согласования каталога в тестовые графы, которые
/// не проверяют массовое согласование открытой выдачи.
mixin CatalogReconciliationTestFallback {
  Future<Result<IntentionCatalogReconciliationOutcome>>
  getCatalogReconciliationPortion(
    IntentionCatalogReconciliationQuery query,
  ) async => const ResultFailure(IntentionUnexpectedFailure());
}
