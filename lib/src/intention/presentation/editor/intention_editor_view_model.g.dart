// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'intention_editor_view_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(IntentionEditorViewModel)
final intentionEditorViewModelProvider = IntentionEditorViewModelFamily._();

final class IntentionEditorViewModelProvider
    extends $NotifierProvider<IntentionEditorViewModel, IntentionEditorState> {
  IntentionEditorViewModelProvider._({
    required IntentionEditorViewModelFamily super.from,
    required IntentionCreationFormKey super.argument,
  }) : super(
         retry: null,
         name: r'intentionEditorViewModelProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$intentionEditorViewModelHash();

  @override
  String toString() {
    return r'intentionEditorViewModelProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  IntentionEditorViewModel create() => IntentionEditorViewModel();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(IntentionEditorState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<IntentionEditorState>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is IntentionEditorViewModelProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$intentionEditorViewModelHash() =>
    r'ee2d12a5a31c0022b9b6ff61d75fa4d203b6b762';

final class IntentionEditorViewModelFamily extends $Family
    with
        $ClassFamilyOverride<
          IntentionEditorViewModel,
          IntentionEditorState,
          IntentionEditorState,
          IntentionEditorState,
          IntentionCreationFormKey
        > {
  IntentionEditorViewModelFamily._()
    : super(
        retry: null,
        name: r'intentionEditorViewModelProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  IntentionEditorViewModelProvider call(IntentionCreationFormKey formKey) =>
      IntentionEditorViewModelProvider._(argument: formKey, from: this);

  @override
  String toString() => r'intentionEditorViewModelProvider';
}

abstract class _$IntentionEditorViewModel
    extends $Notifier<IntentionEditorState> {
  late final _$args = ref.$arg as IntentionCreationFormKey;
  IntentionCreationFormKey get formKey => _$args;

  IntentionEditorState build(IntentionCreationFormKey formKey);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<IntentionEditorState, IntentionEditorState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<IntentionEditorState, IntentionEditorState>,
              IntentionEditorState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
