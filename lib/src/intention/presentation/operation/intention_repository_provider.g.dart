// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'intention_repository_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(intentionRepository)
final intentionRepositoryProvider = IntentionRepositoryProvider._();

final class IntentionRepositoryProvider
    extends
        $FunctionalProvider<
          IntentionRepository,
          IntentionRepository,
          IntentionRepository
        >
    with $Provider<IntentionRepository> {
  IntentionRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'intentionRepositoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$intentionRepositoryHash();

  @$internal
  @override
  $ProviderElement<IntentionRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  IntentionRepository create(Ref ref) {
    return intentionRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(IntentionRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<IntentionRepository>(value),
    );
  }
}

String _$intentionRepositoryHash() =>
    r'5438e094d0b90dc8c02da4748350a9ad8e9a9c68';
