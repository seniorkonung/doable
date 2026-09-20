// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'relation_neighborhood_paging_policy.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(relationNeighborhoodPagingPolicy)
final relationNeighborhoodPagingPolicyProvider =
    RelationNeighborhoodPagingPolicyProvider._();

final class RelationNeighborhoodPagingPolicyProvider
    extends
        $FunctionalProvider<
          RelationNeighborhoodPagingPolicy,
          RelationNeighborhoodPagingPolicy,
          RelationNeighborhoodPagingPolicy
        >
    with $Provider<RelationNeighborhoodPagingPolicy> {
  RelationNeighborhoodPagingPolicyProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'relationNeighborhoodPagingPolicyProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$relationNeighborhoodPagingPolicyHash();

  @$internal
  @override
  $ProviderElement<RelationNeighborhoodPagingPolicy> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  RelationNeighborhoodPagingPolicy create(Ref ref) {
    return relationNeighborhoodPagingPolicy(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(RelationNeighborhoodPagingPolicy value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<RelationNeighborhoodPagingPolicy>(
        value,
      ),
    );
  }
}

String _$relationNeighborhoodPagingPolicyHash() =>
    r'f4716f173fea2bfd161e21a269fc576854b0d915';
