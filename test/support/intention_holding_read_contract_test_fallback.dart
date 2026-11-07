import 'package:doable/src/intention/application/intention_holding.dart';
import 'package:doable/src/intention/domain/intention_id.dart';

/// Подставляет явный отказ в тестовые графы, не читающие удержание.
mixin IntentionHoldingReadContractTestFallback
    implements IntentionHoldingReadContract {
  @override
  Future<IntentionHoldingResult> getIntentionHolding(
    Set<IntentionId> ids,
  ) async => const IntentionHoldingFailed();
}
