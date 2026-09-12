// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'intention_details_view_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(_DetailObservationGenerationController)
final _detailObservationGenerationControllerProvider =
    _DetailObservationGenerationControllerFamily._();

final class _DetailObservationGenerationControllerProvider
    extends
        $NotifierProvider<
          _DetailObservationGenerationController,
          _DetailObservationGeneration
        > {
  _DetailObservationGenerationControllerProvider._({
    required _DetailObservationGenerationControllerFamily super.from,
    required IntentionId super.argument,
  }) : super(
         retry: null,
         name: r'_detailObservationGenerationControllerProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() =>
      _$_detailObservationGenerationControllerHash();

  @override
  String toString() {
    return r'_detailObservationGenerationControllerProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  _DetailObservationGenerationController create() =>
      _DetailObservationGenerationController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(_DetailObservationGeneration value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<_DetailObservationGeneration>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is _DetailObservationGenerationControllerProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$_detailObservationGenerationControllerHash() =>
    r'466070d2489d9988d9ef5e435ed0cd31de3978eb';

final class _DetailObservationGenerationControllerFamily extends $Family
    with
        $ClassFamilyOverride<
          _DetailObservationGenerationController,
          _DetailObservationGeneration,
          _DetailObservationGeneration,
          _DetailObservationGeneration,
          IntentionId
        > {
  _DetailObservationGenerationControllerFamily._()
    : super(
        retry: null,
        name: r'_detailObservationGenerationControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  _DetailObservationGenerationControllerProvider call(
    IntentionId intentionId,
  ) => _DetailObservationGenerationControllerProvider._(
    argument: intentionId,
    from: this,
  );

  @override
  String toString() => r'_detailObservationGenerationControllerProvider';
}

abstract class _$DetailObservationGenerationController
    extends $Notifier<_DetailObservationGeneration> {
  late final _$args = ref.$arg as IntentionId;
  IntentionId get intentionId => _$args;

  _DetailObservationGeneration build(IntentionId intentionId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<_DetailObservationGeneration, _DetailObservationGeneration>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                _DetailObservationGeneration,
                _DetailObservationGeneration
              >,
              _DetailObservationGeneration,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}

@ProviderFor(_intentionDetailsObservation)
final _intentionDetailsObservationProvider =
    _IntentionDetailsObservationFamily._();

final class _IntentionDetailsObservationProvider
    extends
        $FunctionalProvider<
          AsyncValue<Result<Intention?>>,
          Result<Intention?>,
          Stream<Result<Intention?>>
        >
    with
        $FutureModifier<Result<Intention?>>,
        $StreamProvider<Result<Intention?>> {
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
  $StreamProviderElement<Result<Intention?>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<Result<Intention?>> create(Ref ref) {
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
    r'9edc1895689c3d93094b3ba534ece1ef21c5949e';

final class _IntentionDetailsObservationFamily extends $Family
    with
        $FunctionalFamilyOverride<
          Stream<Result<Intention?>>,
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
    r'beed3dd7789da57d402e7c77c76dc3c5b41e7595';

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
