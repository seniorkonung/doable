// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'relation_neighborhood_view_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Управляет первым чтением и подгрузкой одной выбранной группы связей.
///
/// Одновременно выполняется не более одного чтения группы. Ответ принимается
/// только для текущего поколения запроса: смена группы, повторное первое
/// чтение и обновление делают прежние ответы непригодными.

@ProviderFor(RelationNeighborhoodViewModel)
final relationNeighborhoodViewModelProvider =
    RelationNeighborhoodViewModelFamily._();

/// Управляет первым чтением и подгрузкой одной выбранной группы связей.
///
/// Одновременно выполняется не более одного чтения группы. Ответ принимается
/// только для текущего поколения запроса: смена группы, повторное первое
/// чтение и обновление делают прежние ответы непригодными.
final class RelationNeighborhoodViewModelProvider
    extends
        $NotifierProvider<
          RelationNeighborhoodViewModel,
          RelationNeighborhoodState
        > {
  /// Управляет первым чтением и подгрузкой одной выбранной группы связей.
  ///
  /// Одновременно выполняется не более одного чтения группы. Ответ принимается
  /// только для текущего поколения запроса: смена группы, повторное первое
  /// чтение и обновление делают прежние ответы непригодными.
  RelationNeighborhoodViewModelProvider._({
    required RelationNeighborhoodViewModelFamily super.from,
    required IntentionId super.argument,
  }) : super(
         retry: null,
         name: r'relationNeighborhoodViewModelProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$relationNeighborhoodViewModelHash();

  @override
  String toString() {
    return r'relationNeighborhoodViewModelProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  RelationNeighborhoodViewModel create() => RelationNeighborhoodViewModel();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(RelationNeighborhoodState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<RelationNeighborhoodState>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is RelationNeighborhoodViewModelProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$relationNeighborhoodViewModelHash() =>
    r'ac0c2705857f15bed25e1ecaf230f6cc07be29ca';

/// Управляет первым чтением и подгрузкой одной выбранной группы связей.
///
/// Одновременно выполняется не более одного чтения группы. Ответ принимается
/// только для текущего поколения запроса: смена группы, повторное первое
/// чтение и обновление делают прежние ответы непригодными.

final class RelationNeighborhoodViewModelFamily extends $Family
    with
        $ClassFamilyOverride<
          RelationNeighborhoodViewModel,
          RelationNeighborhoodState,
          RelationNeighborhoodState,
          RelationNeighborhoodState,
          IntentionId
        > {
  RelationNeighborhoodViewModelFamily._()
    : super(
        retry: null,
        name: r'relationNeighborhoodViewModelProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Управляет первым чтением и подгрузкой одной выбранной группы связей.
  ///
  /// Одновременно выполняется не более одного чтения группы. Ответ принимается
  /// только для текущего поколения запроса: смена группы, повторное первое
  /// чтение и обновление делают прежние ответы непригодными.

  RelationNeighborhoodViewModelProvider call(IntentionId intentionId) =>
      RelationNeighborhoodViewModelProvider._(
        argument: intentionId,
        from: this,
      );

  @override
  String toString() => r'relationNeighborhoodViewModelProvider';
}

/// Управляет первым чтением и подгрузкой одной выбранной группы связей.
///
/// Одновременно выполняется не более одного чтения группы. Ответ принимается
/// только для текущего поколения запроса: смена группы, повторное первое
/// чтение и обновление делают прежние ответы непригодными.

abstract class _$RelationNeighborhoodViewModel
    extends $Notifier<RelationNeighborhoodState> {
  late final _$args = ref.$arg as IntentionId;
  IntentionId get intentionId => _$args;

  RelationNeighborhoodState build(IntentionId intentionId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<RelationNeighborhoodState, RelationNeighborhoodState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<RelationNeighborhoodState, RelationNeighborhoodState>,
              RelationNeighborhoodState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
