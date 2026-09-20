// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'intention_catalog_view_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(IntentionCatalogViewModel)
final intentionCatalogViewModelProvider = IntentionCatalogViewModelProvider._();

final class IntentionCatalogViewModelProvider
    extends
        $AsyncNotifierProvider<
          IntentionCatalogViewModel,
          IntentionCatalogState
        > {
  IntentionCatalogViewModelProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'intentionCatalogViewModelProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$intentionCatalogViewModelHash();

  @$internal
  @override
  IntentionCatalogViewModel create() => IntentionCatalogViewModel();
}

String _$intentionCatalogViewModelHash() =>
    r'4d4c2b91626394810672644cebd48f792ae27d55';

abstract class _$IntentionCatalogViewModel
    extends $AsyncNotifier<IntentionCatalogState> {
  FutureOr<IntentionCatalogState> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<AsyncValue<IntentionCatalogState>, IntentionCatalogState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AsyncValue<IntentionCatalogState>,
                IntentionCatalogState
              >,
              AsyncValue<IntentionCatalogState>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
