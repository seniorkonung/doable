// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'tag_catalog_view_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(TagCatalogViewModel)
final tagCatalogViewModelProvider = TagCatalogViewModelProvider._();

final class TagCatalogViewModelProvider
    extends $NotifierProvider<TagCatalogViewModel, TagCatalogState> {
  TagCatalogViewModelProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'tagCatalogViewModelProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$tagCatalogViewModelHash();

  @$internal
  @override
  TagCatalogViewModel create() => TagCatalogViewModel();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(TagCatalogState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<TagCatalogState>(value),
    );
  }
}

String _$tagCatalogViewModelHash() =>
    r'9d004aa706e9fed6790b99ebe451a07cd8004bb9';

abstract class _$TagCatalogViewModel extends $Notifier<TagCatalogState> {
  TagCatalogState build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<TagCatalogState, TagCatalogState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<TagCatalogState, TagCatalogState>,
              TagCatalogState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
