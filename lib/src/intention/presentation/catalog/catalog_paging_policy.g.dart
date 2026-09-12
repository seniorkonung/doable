// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'catalog_paging_policy.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(catalogPagingPolicy)
final catalogPagingPolicyProvider = CatalogPagingPolicyProvider._();

final class CatalogPagingPolicyProvider
    extends
        $FunctionalProvider<
          CatalogPagingPolicy,
          CatalogPagingPolicy,
          CatalogPagingPolicy
        >
    with $Provider<CatalogPagingPolicy> {
  CatalogPagingPolicyProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'catalogPagingPolicyProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$catalogPagingPolicyHash();

  @$internal
  @override
  $ProviderElement<CatalogPagingPolicy> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  CatalogPagingPolicy create(Ref ref) {
    return catalogPagingPolicy(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(CatalogPagingPolicy value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<CatalogPagingPolicy>(value),
    );
  }
}

String _$catalogPagingPolicyHash() =>
    r'2d0500604b6f1603a61b01269602051bac5e6301';
