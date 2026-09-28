// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'tag_navigation_view_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(TagNavigationViewModel)
final tagNavigationViewModelProvider = TagNavigationViewModelFamily._();

final class TagNavigationViewModelProvider
    extends $NotifierProvider<TagNavigationViewModel, TagNavigationState> {
  TagNavigationViewModelProvider._({
    required TagNavigationViewModelFamily super.from,
    required TagId super.argument,
  }) : super(
         retry: null,
         name: r'tagNavigationViewModelProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$tagNavigationViewModelHash();

  @override
  String toString() {
    return r'tagNavigationViewModelProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  TagNavigationViewModel create() => TagNavigationViewModel();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(TagNavigationState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<TagNavigationState>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is TagNavigationViewModelProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$tagNavigationViewModelHash() =>
    r'7613073e3a8ea3a6f6c3e52367a9d4f4f1887756';

final class TagNavigationViewModelFamily extends $Family
    with
        $ClassFamilyOverride<
          TagNavigationViewModel,
          TagNavigationState,
          TagNavigationState,
          TagNavigationState,
          TagId
        > {
  TagNavigationViewModelFamily._()
    : super(
        retry: null,
        name: r'tagNavigationViewModelProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  TagNavigationViewModelProvider call(TagId tagId) =>
      TagNavigationViewModelProvider._(argument: tagId, from: this);

  @override
  String toString() => r'tagNavigationViewModelProvider';
}

abstract class _$TagNavigationViewModel extends $Notifier<TagNavigationState> {
  late final _$args = ref.$arg as TagId;
  TagId get tagId => _$args;

  TagNavigationState build(TagId tagId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<TagNavigationState, TagNavigationState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<TagNavigationState, TagNavigationState>,
              TagNavigationState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
