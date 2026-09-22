// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'intention_details_view_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(_intentionDetailsObservation)
final _intentionDetailsObservationProvider =
    _IntentionDetailsObservationFamily._();

final class _IntentionDetailsObservationProvider
    extends
        $FunctionalProvider<
          AsyncValue<Result<GraphSnapshot<application.IntentionDetails?>>>,
          Result<GraphSnapshot<application.IntentionDetails?>>,
          Stream<Result<GraphSnapshot<application.IntentionDetails?>>>
        >
    with
        $FutureModifier<Result<GraphSnapshot<application.IntentionDetails?>>>,
        $StreamProvider<Result<GraphSnapshot<application.IntentionDetails?>>> {
  _IntentionDetailsObservationProvider._({
    required _IntentionDetailsObservationFamily super.from,
    required (IntentionId, _DetailObservationGeneration) super.argument,
  }) : super(
         retry: null,
         name: r'_intentionDetailsObservationProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$_intentionDetailsObservationHash();

  @override
  String toString() {
    return r'_intentionDetailsObservationProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  $StreamProviderElement<Result<GraphSnapshot<application.IntentionDetails?>>>
  $createElement($ProviderPointer pointer) => $StreamProviderElement(pointer);

  @override
  Stream<Result<GraphSnapshot<application.IntentionDetails?>>> create(Ref ref) {
    final argument =
        this.argument as (IntentionId, _DetailObservationGeneration);
    return _intentionDetailsObservation(ref, argument.$1, argument.$2);
  }

  @override
  bool operator ==(Object other) {
    return other is _IntentionDetailsObservationProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$_intentionDetailsObservationHash() =>
    r'28ef8917f553b0157c62e11bf2027bb97a188667';

final class _IntentionDetailsObservationFamily extends $Family
    with
        $FunctionalFamilyOverride<
          Stream<Result<GraphSnapshot<application.IntentionDetails?>>>,
          (IntentionId, _DetailObservationGeneration)
        > {
  _IntentionDetailsObservationFamily._()
    : super(
        retry: null,
        name: r'_intentionDetailsObservationProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  _IntentionDetailsObservationProvider call(
    IntentionId intentionId,
    _DetailObservationGeneration generation,
  ) => _IntentionDetailsObservationProvider._(
    argument: (intentionId, generation),
    from: this,
  );

  @override
  String toString() => r'_intentionDetailsObservationProvider';
}

@ProviderFor(IntentionDetailsViewModel)
final intentionDetailsViewModelProvider = IntentionDetailsViewModelFamily._();

final class IntentionDetailsViewModelProvider
    extends
        $NotifierProvider<IntentionDetailsViewModel, IntentionDetailsState> {
  IntentionDetailsViewModelProvider._({
    required IntentionDetailsViewModelFamily super.from,
    required IntentionId super.argument,
  }) : super(
         retry: null,
         name: r'intentionDetailsViewModelProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$intentionDetailsViewModelHash();

  @override
  String toString() {
    return r'intentionDetailsViewModelProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  IntentionDetailsViewModel create() => IntentionDetailsViewModel();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(IntentionDetailsState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<IntentionDetailsState>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is IntentionDetailsViewModelProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$intentionDetailsViewModelHash() =>
    r'9282993a707f93dc9c9bbd754e1b040af0717db1';

final class IntentionDetailsViewModelFamily extends $Family
    with
        $ClassFamilyOverride<
          IntentionDetailsViewModel,
          IntentionDetailsState,
          IntentionDetailsState,
          IntentionDetailsState,
          IntentionId
        > {
  IntentionDetailsViewModelFamily._()
    : super(
        retry: null,
        name: r'intentionDetailsViewModelProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  IntentionDetailsViewModelProvider call(IntentionId intentionId) =>
      IntentionDetailsViewModelProvider._(argument: intentionId, from: this);

  @override
  String toString() => r'intentionDetailsViewModelProvider';
}

abstract class _$IntentionDetailsViewModel
    extends $Notifier<IntentionDetailsState> {
  late final _$args = ref.$arg as IntentionId;
  IntentionId get intentionId => _$args;

  IntentionDetailsState build(IntentionId intentionId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<IntentionDetailsState, IntentionDetailsState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<IntentionDetailsState, IntentionDetailsState>,
              IntentionDetailsState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
