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
    required IntentionId super.argument,
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
    r'328adafcd523590cf5354cde38de3579d414365e';

final class TagAssignmentsViewModelFamily extends $Family
    with
        $ClassFamilyOverride<
          TagAssignmentsViewModel,
          TagAssignmentsState,
          TagAssignmentsState,
          TagAssignmentsState,
          IntentionId
        > {
  TagAssignmentsViewModelFamily._()
    : super(
        retry: null,
        name: r'tagAssignmentsViewModelProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  TagAssignmentsViewModelProvider call(IntentionId intentionId) =>
      TagAssignmentsViewModelProvider._(argument: intentionId, from: this);

  @override
  String toString() => r'tagAssignmentsViewModelProvider';
}

abstract class _$TagAssignmentsViewModel
    extends $Notifier<TagAssignmentsState> {
  late final _$args = ref.$arg as IntentionId;
  IntentionId get intentionId => _$args;

  TagAssignmentsState build(IntentionId intentionId);
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
