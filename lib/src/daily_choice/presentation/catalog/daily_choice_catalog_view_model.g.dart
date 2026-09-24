// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'daily_choice_catalog_view_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Согласовывает ограниченную загруженную часть с подтверждённым графом.

@ProviderFor(DailyChoiceCatalogViewModel)
final dailyChoiceCatalogViewModelProvider =
    DailyChoiceCatalogViewModelProvider._();

/// Согласовывает ограниченную загруженную часть с подтверждённым графом.
final class DailyChoiceCatalogViewModelProvider
    extends
        $NotifierProvider<
          DailyChoiceCatalogViewModel,
          DailyChoiceCatalogState
        > {
  /// Согласовывает ограниченную загруженную часть с подтверждённым графом.
  DailyChoiceCatalogViewModelProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'dailyChoiceCatalogViewModelProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$dailyChoiceCatalogViewModelHash();

  @$internal
  @override
  DailyChoiceCatalogViewModel create() => DailyChoiceCatalogViewModel();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(DailyChoiceCatalogState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<DailyChoiceCatalogState>(value),
    );
  }
}

String _$dailyChoiceCatalogViewModelHash() =>
    r'46028122163b8541901e6ca06941cd56e73da99b';

/// Согласовывает ограниченную загруженную часть с подтверждённым графом.

abstract class _$DailyChoiceCatalogViewModel
    extends $Notifier<DailyChoiceCatalogState> {
  DailyChoiceCatalogState build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<DailyChoiceCatalogState, DailyChoiceCatalogState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<DailyChoiceCatalogState, DailyChoiceCatalogState>,
              DailyChoiceCatalogState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
