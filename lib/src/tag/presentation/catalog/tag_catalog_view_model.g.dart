// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'tag_catalog_view_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(TagCatalogViewModel)
final tagCatalogViewModelProvider = TagCatalogViewModelFamily._();

final class TagCatalogViewModelProvider
    extends $NotifierProvider<TagCatalogViewModel, TagCatalogState> {
  TagCatalogViewModelProvider._({
    required TagCatalogViewModelFamily super.from,
    required TagCatalogMode super.argument,
  }) : super(
         retry: null,
         name: r'tagCatalogViewModelProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$tagCatalogViewModelHash();

  @override
  String toString() {
    return r'tagCatalogViewModelProvider'
        ''
        '($argument)';
  }

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

  @override
  bool operator ==(Object other) {
    return other is TagCatalogViewModelProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$tagCatalogViewModelHash() =>
    r'232b7f6ebd3a52fd64c249cb0ee5712a84bbaa50';

final class TagCatalogViewModelFamily extends $Family
    with
        $ClassFamilyOverride<
          TagCatalogViewModel,
          TagCatalogState,
          TagCatalogState,
          TagCatalogState,
          TagCatalogMode
        > {
  TagCatalogViewModelFamily._()
    : super(
        retry: null,
        name: r'tagCatalogViewModelProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  TagCatalogViewModelProvider call({
    TagCatalogMode mode = const TagCatalogBrowseMode(),
  }) => TagCatalogViewModelProvider._(argument: mode, from: this);

  @override
  String toString() => r'tagCatalogViewModelProvider';
}

abstract class _$TagCatalogViewModel extends $Notifier<TagCatalogState> {
  late final _$args = ref.$arg as TagCatalogMode;
  TagCatalogMode get mode => _$args;

  TagCatalogState build({TagCatalogMode mode = const TagCatalogBrowseMode()});
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
    return element.handleCreate(ref, () => build(mode: _$args));
  }
}
