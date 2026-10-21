// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'home_statistics_view_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(HomeStatisticsViewModel)
final homeStatisticsViewModelProvider = HomeStatisticsViewModelProvider._();

final class HomeStatisticsViewModelProvider
    extends $NotifierProvider<HomeStatisticsViewModel, HomeStatisticsState> {
  HomeStatisticsViewModelProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'homeStatisticsViewModelProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$homeStatisticsViewModelHash();

  @$internal
  @override
  HomeStatisticsViewModel create() => HomeStatisticsViewModel();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(HomeStatisticsState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<HomeStatisticsState>(value),
    );
  }
}

String _$homeStatisticsViewModelHash() =>
    r'0765078785085bb71d29b449fc1b8e5c9273193b';

abstract class _$HomeStatisticsViewModel
    extends $Notifier<HomeStatisticsState> {
  HomeStatisticsState build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<HomeStatisticsState, HomeStatisticsState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<HomeStatisticsState, HomeStatisticsState>,
              HomeStatisticsState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
