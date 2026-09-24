// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'choice_path_view_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Управляет одним обходом. Ответы принимаются только поколением текущего
/// черновика, экранной сессией и ревизией подтверждённого снимка.

@ProviderFor(ChoicePathViewModel)
final choicePathViewModelProvider = ChoicePathViewModelFamily._();

/// Управляет одним обходом. Ответы принимаются только поколением текущего
/// черновика, экранной сессией и ревизией подтверждённого снимка.
final class ChoicePathViewModelProvider
    extends $NotifierProvider<ChoicePathViewModel, ChoicePathState> {
  /// Управляет одним обходом. Ответы принимаются только поколением текущего
  /// черновика, экранной сессией и ревизией подтверждённого снимка.
  ChoicePathViewModelProvider._({
    required ChoicePathViewModelFamily super.from,
    required (IntentionId, {ChoicePathDraftDirection direction}) super.argument,
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
        '$argument';
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
    r'14c74e5d9e572397fa2c45b2efb6e9870e8b8bab';

/// Управляет одним обходом. Ответы принимаются только поколением текущего
/// черновика, экранной сессией и ревизией подтверждённого снимка.

final class ChoicePathViewModelFamily extends $Family
    with
        $ClassFamilyOverride<
          ChoicePathViewModel,
          ChoicePathState,
          ChoicePathState,
          ChoicePathState,
          (IntentionId, {ChoicePathDraftDirection direction})
        > {
  ChoicePathViewModelFamily._()
    : super(
        retry: null,
        name: r'choicePathViewModelProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Управляет одним обходом. Ответы принимаются только поколением текущего
  /// черновика, экранной сессией и ревизией подтверждённого снимка.

  ChoicePathViewModelProvider call(
    IntentionId startingIntentionId, {
    ChoicePathDraftDirection direction = ChoicePathDraftDirection.topDown,
  }) => ChoicePathViewModelProvider._(
    argument: (startingIntentionId, direction: direction),
    from: this,
  );

  @override
  String toString() => r'choicePathViewModelProvider';
}

/// Управляет одним обходом. Ответы принимаются только поколением текущего
/// черновика, экранной сессией и ревизией подтверждённого снимка.

abstract class _$ChoicePathViewModel extends $Notifier<ChoicePathState> {
  late final _$args =
      ref.$arg as (IntentionId, {ChoicePathDraftDirection direction});
  IntentionId get startingIntentionId => _$args.$1;
  ChoicePathDraftDirection get direction => _$args.direction;

  ChoicePathState build(
    IntentionId startingIntentionId, {
    ChoicePathDraftDirection direction = ChoicePathDraftDirection.topDown,
  });
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
    return element.handleCreate(
      ref,
      () => build(_$args.$1, direction: _$args.direction),
    );
  }
}
