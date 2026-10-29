// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'relation_group_paging_policy.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(relationGroupPagingPolicy)
final relationGroupPagingPolicyProvider = RelationGroupPagingPolicyProvider._();

final class RelationGroupPagingPolicyProvider
    extends
        $FunctionalProvider<
          RelationGroupPagingPolicy,
          RelationGroupPagingPolicy,
          RelationGroupPagingPolicy
        >
    with $Provider<RelationGroupPagingPolicy> {
  RelationGroupPagingPolicyProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'relationGroupPagingPolicyProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$relationGroupPagingPolicyHash();

  @$internal
  @override
  $ProviderElement<RelationGroupPagingPolicy> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  RelationGroupPagingPolicy create(Ref ref) {
    return relationGroupPagingPolicy(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(RelationGroupPagingPolicy value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<RelationGroupPagingPolicy>(value),
    );
  }
}

String _$relationGroupPagingPolicyHash() =>
    r'5922a43687ce78031d93b047f87974200cb4bde1';
