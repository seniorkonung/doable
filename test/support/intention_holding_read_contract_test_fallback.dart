import 'package:doable/src/intention/application/cascade/intention_cascade.dart';
import 'package:doable/src/intention/application/intention_holding.dart';
import 'package:doable/src/intention/domain/intention_id.dart';

/// Подставляет явные отказы в тестовые графы, не читающие удержание и
/// предпросмотр каскада.
mixin IntentionHoldingReadContractTestFallback
    implements
        IntentionHoldingReadContract,
        IntentionCascadePreviewReadContract {
  @override
  Future<IntentionHoldingResult> getIntentionHolding(
    Set<IntentionId> ids,
  ) async => const IntentionHoldingFailed();

  @override
  Future<CascadePreviewResult> previewCascade(
    CascadeSubject subject,
    CascadeOperation operation,
  ) async => const CascadePreviewUnexpected();
}
