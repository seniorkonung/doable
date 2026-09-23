// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'relation_details_view_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(_relationDetailsObservation)
final _relationDetailsObservationProvider =
    _RelationDetailsObservationFamily._();

final class _RelationDetailsObservationProvider
    extends
        $FunctionalProvider<
          AsyncValue<LongTermRelationReadResult>,
          LongTermRelationReadResult,
          Stream<LongTermRelationReadResult>
        >
    with
        $FutureModifier<LongTermRelationReadResult>,
        $StreamProvider<LongTermRelationReadResult> {
  _RelationDetailsObservationProvider._({
    required _RelationDetailsObservationFamily super.from,
    required (LongTermRelationId, _RelationObservationGeneration)
    super.argument,
  }) : super(
         retry: null,
         name: r'_relationDetailsObservationProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$_relationDetailsObservationHash();

  @override
  String toString() {
    return r'_relationDetailsObservationProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  $StreamProviderElement<LongTermRelationReadResult> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<LongTermRelationReadResult> create(Ref ref) {
    final argument =
        this.argument as (LongTermRelationId, _RelationObservationGeneration);
    return _relationDetailsObservation(ref, argument.$1, argument.$2);
  }

  @override
  bool operator ==(Object other) {
    return other is _RelationDetailsObservationProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$_relationDetailsObservationHash() =>
    r'1bb8772044a136de56e5da5a3fc8c7065457181c';

final class _RelationDetailsObservationFamily extends $Family
    with
        $FunctionalFamilyOverride<
          Stream<LongTermRelationReadResult>,
          (LongTermRelationId, _RelationObservationGeneration)
        > {
  _RelationDetailsObservationFamily._()
    : super(
        retry: null,
        name: r'_relationDetailsObservationProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  _RelationDetailsObservationProvider call(
    LongTermRelationId relationId,
    _RelationObservationGeneration generation,
  ) => _RelationDetailsObservationProvider._(
    argument: (relationId, generation),
    from: this,
  );

  @override
  String toString() => r'_relationDetailsObservationProvider';
}

/// Подробные данные одной связи с актуальными участниками.
///
/// Наблюдение перечитывает зависимости самостоятельно, поэтому просмотр не
/// подписывается на весь граф. Запоздалый ответ более старой ревизии или
/// прежнего поколения не отменяет подтверждённые данные.

@ProviderFor(RelationDetailsViewModel)
final relationDetailsViewModelProvider = RelationDetailsViewModelFamily._();

/// Подробные данные одной связи с актуальными участниками.
///
/// Наблюдение перечитывает зависимости самостоятельно, поэтому просмотр не
/// подписывается на весь граф. Запоздалый ответ более старой ревизии или
/// прежнего поколения не отменяет подтверждённые данные.
final class RelationDetailsViewModelProvider
    extends $NotifierProvider<RelationDetailsViewModel, RelationDetailsState> {
  /// Подробные данные одной связи с актуальными участниками.
  ///
  /// Наблюдение перечитывает зависимости самостоятельно, поэтому просмотр не
  /// подписывается на весь граф. Запоздалый ответ более старой ревизии или
  /// прежнего поколения не отменяет подтверждённые данные.
  RelationDetailsViewModelProvider._({
    required RelationDetailsViewModelFamily super.from,
    required LongTermRelationId super.argument,
  }) : super(
         retry: null,
         name: r'relationDetailsViewModelProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$relationDetailsViewModelHash();

  @override
  String toString() {
    return r'relationDetailsViewModelProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  RelationDetailsViewModel create() => RelationDetailsViewModel();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(RelationDetailsState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<RelationDetailsState>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is RelationDetailsViewModelProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$relationDetailsViewModelHash() =>
    r'c87fbb9541f9be8ac1abe73bf85ffbd4d72b3e2a';

/// Подробные данные одной связи с актуальными участниками.
///
/// Наблюдение перечитывает зависимости самостоятельно, поэтому просмотр не
/// подписывается на весь граф. Запоздалый ответ более старой ревизии или
/// прежнего поколения не отменяет подтверждённые данные.

final class RelationDetailsViewModelFamily extends $Family
    with
        $ClassFamilyOverride<
          RelationDetailsViewModel,
          RelationDetailsState,
          RelationDetailsState,
          RelationDetailsState,
          LongTermRelationId
        > {
  RelationDetailsViewModelFamily._()
    : super(
        retry: null,
        name: r'relationDetailsViewModelProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Подробные данные одной связи с актуальными участниками.
  ///
  /// Наблюдение перечитывает зависимости самостоятельно, поэтому просмотр не
  /// подписывается на весь граф. Запоздалый ответ более старой ревизии или
  /// прежнего поколения не отменяет подтверждённые данные.

  RelationDetailsViewModelProvider call(LongTermRelationId relationId) =>
      RelationDetailsViewModelProvider._(argument: relationId, from: this);

  @override
  String toString() => r'relationDetailsViewModelProvider';
}

/// Подробные данные одной связи с актуальными участниками.
///
/// Наблюдение перечитывает зависимости самостоятельно, поэтому просмотр не
/// подписывается на весь граф. Запоздалый ответ более старой ревизии или
/// прежнего поколения не отменяет подтверждённые данные.

abstract class _$RelationDetailsViewModel
    extends $Notifier<RelationDetailsState> {
  late final _$args = ref.$arg as LongTermRelationId;
  LongTermRelationId get relationId => _$args;

  RelationDetailsState build(LongTermRelationId relationId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<RelationDetailsState, RelationDetailsState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<RelationDetailsState, RelationDetailsState>,
              RelationDetailsState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
