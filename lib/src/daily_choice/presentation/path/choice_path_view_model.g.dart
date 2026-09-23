// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'choice_path_view_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Управляет одним верхним обходом. Ответы принимаются только поколением
/// текущего префикса и ревизией подтверждённого снимка.

@ProviderFor(ChoicePathViewModel)
final choicePathViewModelProvider = ChoicePathViewModelFamily._();

/// Управляет одним верхним обходом. Ответы принимаются только поколением
/// текущего префикса и ревизией подтверждённого снимка.
final class ChoicePathViewModelProvider
    extends $NotifierProvider<ChoicePathViewModel, ChoicePathState> {
  /// Управляет одним верхним обходом. Ответы принимаются только поколением
  /// текущего префикса и ревизией подтверждённого снимка.
  ChoicePathViewModelProvider._({
    required ChoicePathViewModelFamily super.from,
    required IntentionId super.argument,
  }) : super(
         retry: null,
         name: r'choicePathViewModelProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$choicePathViewModelHash();

  @override
  String toString() {
    return r'choicePathViewModelProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  ChoicePathViewModel create() => ChoicePathViewModel();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ChoicePathState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ChoicePathState>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ChoicePathViewModelProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$choicePathViewModelHash() =>
    r'dc5ee20c7d8646b3e768c1fe184844d999ff56d3';

/// Управляет одним верхним обходом. Ответы принимаются только поколением
/// текущего префикса и ревизией подтверждённого снимка.

final class ChoicePathViewModelFamily extends $Family
    with
        $ClassFamilyOverride<
          ChoicePathViewModel,
          ChoicePathState,
          ChoicePathState,
          ChoicePathState,
          IntentionId
        > {
  ChoicePathViewModelFamily._()
    : super(
        retry: null,
        name: r'choicePathViewModelProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Управляет одним верхним обходом. Ответы принимаются только поколением
  /// текущего префикса и ревизией подтверждённого снимка.

  ChoicePathViewModelProvider call(IntentionId sourceIntentionId) =>
      ChoicePathViewModelProvider._(argument: sourceIntentionId, from: this);

  @override
  String toString() => r'choicePathViewModelProvider';
}

/// Управляет одним верхним обходом. Ответы принимаются только поколением
/// текущего префикса и ревизией подтверждённого снимка.

abstract class _$ChoicePathViewModel extends $Notifier<ChoicePathState> {
  late final _$args = ref.$arg as IntentionId;
  IntentionId get sourceIntentionId => _$args;

  ChoicePathState build(IntentionId sourceIntentionId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<ChoicePathState, ChoicePathState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<ChoicePathState, ChoicePathState>,
              ChoicePathState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
