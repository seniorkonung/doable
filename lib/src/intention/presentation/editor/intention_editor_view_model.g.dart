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
    required IntentionEditorSession super.argument,
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
    r'7259de64a3e476ae3fe5c469b464869a39c80d2f';

final class IntentionEditorViewModelFamily extends $Family
    with
        $ClassFamilyOverride<
          IntentionEditorViewModel,
          IntentionEditorState,
          IntentionEditorState,
          IntentionEditorState,
          IntentionEditorSession
        > {
  IntentionEditorViewModelFamily._()
    : super(
        retry: null,
        name: r'intentionEditorViewModelProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  IntentionEditorViewModelProvider call(IntentionEditorSession session) =>
      IntentionEditorViewModelProvider._(argument: session, from: this);

  @override
  String toString() => r'intentionEditorViewModelProvider';
}

abstract class _$IntentionEditorViewModel
    extends $Notifier<IntentionEditorState> {
  late final _$args = ref.$arg as IntentionEditorSession;
  IntentionEditorSession get session => _$args;

  IntentionEditorState build(IntentionEditorSession session);
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
