// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'tag_assignments_view_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(TagAssignmentsViewModel)
final tagAssignmentsViewModelProvider = TagAssignmentsViewModelFamily._();

final class TagAssignmentsViewModelProvider
    extends $NotifierProvider<TagAssignmentsViewModel, TagAssignmentsState> {
  TagAssignmentsViewModelProvider._({
    required TagAssignmentsViewModelFamily super.from,
    required TagTarget super.argument,
  }) : super(
         retry: null,
         name: r'tagAssignmentsViewModelProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$tagAssignmentsViewModelHash();

  @override
  String toString() {
    return r'tagAssignmentsViewModelProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  TagAssignmentsViewModel create() => TagAssignmentsViewModel();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(TagAssignmentsState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<TagAssignmentsState>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is TagAssignmentsViewModelProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$tagAssignmentsViewModelHash() =>
    r'a672f5b606a830d833311259d7248ac7bddbb726';

final class TagAssignmentsViewModelFamily extends $Family
    with
        $ClassFamilyOverride<
          TagAssignmentsViewModel,
          TagAssignmentsState,
          TagAssignmentsState,
          TagAssignmentsState,
          TagTarget
        > {
  TagAssignmentsViewModelFamily._()
    : super(
        retry: null,
        name: r'tagAssignmentsViewModelProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  TagAssignmentsViewModelProvider call(TagTarget target) =>
      TagAssignmentsViewModelProvider._(argument: target, from: this);

  @override
  String toString() => r'tagAssignmentsViewModelProvider';
}

abstract class _$TagAssignmentsViewModel
    extends $Notifier<TagAssignmentsState> {
  late final _$args = ref.$arg as TagTarget;
  TagTarget get target => _$args;

  TagAssignmentsState build(TagTarget target);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<TagAssignmentsState, TagAssignmentsState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<TagAssignmentsState, TagAssignmentsState>,
              TagAssignmentsState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
