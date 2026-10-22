// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'tags_panel_view_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(TagsPanelViewModel)
final tagsPanelViewModelProvider = TagsPanelViewModelFamily._();

final class TagsPanelViewModelProvider
    extends $NotifierProvider<TagsPanelViewModel, TagsPanelState> {
  TagsPanelViewModelProvider._({
    required TagsPanelViewModelFamily super.from,
    required TagsPanelOpening super.argument,
  }) : super(
         retry: null,
         name: r'tagsPanelViewModelProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$tagsPanelViewModelHash();

  @override
  String toString() {
    return r'tagsPanelViewModelProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  TagsPanelViewModel create() => TagsPanelViewModel();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(TagsPanelState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<TagsPanelState>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is TagsPanelViewModelProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$tagsPanelViewModelHash() =>
    r'9ba5e4da1098f2ab12368054d1bb936aa9a16b70';

final class TagsPanelViewModelFamily extends $Family
    with
        $ClassFamilyOverride<
          TagsPanelViewModel,
          TagsPanelState,
          TagsPanelState,
          TagsPanelState,
          TagsPanelOpening
        > {
  TagsPanelViewModelFamily._()
    : super(
        retry: null,
        name: r'tagsPanelViewModelProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  TagsPanelViewModelProvider call(TagsPanelOpening opening) =>
      TagsPanelViewModelProvider._(argument: opening, from: this);

  @override
  String toString() => r'tagsPanelViewModelProvider';
}

abstract class _$TagsPanelViewModel extends $Notifier<TagsPanelState> {
  late final _$args = ref.$arg as TagsPanelOpening;
  TagsPanelOpening get opening => _$args;

  TagsPanelState build(TagsPanelOpening opening);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<TagsPanelState, TagsPanelState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<TagsPanelState, TagsPanelState>,
              TagsPanelState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
