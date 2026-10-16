// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'daily_choice_catalog_view_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Публикует согласованную пару и независимо подгружает её секции.

@ProviderFor(DailyChoiceCatalogViewModel)
final dailyChoiceCatalogViewModelProvider =
    DailyChoiceCatalogViewModelFamily._();

/// Публикует согласованную пару и независимо подгружает её секции.
final class DailyChoiceCatalogViewModelProvider
    extends
        $NotifierProvider<
          DailyChoiceCatalogViewModel,
          DailyChoiceCatalogState
        > {
  /// Публикует согласованную пару и независимо подгружает её секции.
  DailyChoiceCatalogViewModelProvider._({
    required DailyChoiceCatalogViewModelFamily super.from,
    required DailyChoiceCatalogInstance super.argument,
  }) : super(
         retry: null,
         name: r'dailyChoiceCatalogViewModelProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$dailyChoiceCatalogViewModelHash();

  @override
  String toString() {
    return r'dailyChoiceCatalogViewModelProvider'
        ''
        '($argument)';
  }

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

  @override
  bool operator ==(Object other) {
    return other is DailyChoiceCatalogViewModelProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$dailyChoiceCatalogViewModelHash() =>
    r'5db3fb21970fc0b600a403b03a046981b5b26e0e';

/// Публикует согласованную пару и независимо подгружает её секции.

final class DailyChoiceCatalogViewModelFamily extends $Family
    with
        $ClassFamilyOverride<
          DailyChoiceCatalogViewModel,
          DailyChoiceCatalogState,
          DailyChoiceCatalogState,
          DailyChoiceCatalogState,
          DailyChoiceCatalogInstance
        > {
  DailyChoiceCatalogViewModelFamily._()
    : super(
        retry: null,
        name: r'dailyChoiceCatalogViewModelProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Публикует согласованную пару и независимо подгружает её секции.

  DailyChoiceCatalogViewModelProvider call(
    DailyChoiceCatalogInstance instance,
  ) => DailyChoiceCatalogViewModelProvider._(argument: instance, from: this);

  @override
  String toString() => r'dailyChoiceCatalogViewModelProvider';
}

/// Публикует согласованную пару и независимо подгружает её секции.

abstract class _$DailyChoiceCatalogViewModel
    extends $Notifier<DailyChoiceCatalogState> {
  late final _$args = ref.$arg as DailyChoiceCatalogInstance;
  DailyChoiceCatalogInstance get instance => _$args;

  DailyChoiceCatalogState build(DailyChoiceCatalogInstance instance);
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
    return element.handleCreate(ref, () => build(_$args));
  }
}
