// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'relation_batch_view_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Отметки принадлежат экземпляру поиска и не зависят от его выдачи.
///
/// Принятая команда выполняется до результата и без поиска: его уход передаёт
/// право предъявления оболочке.

@ProviderFor(RelationBatchViewModel)
final relationBatchViewModelProvider = RelationBatchViewModelFamily._();

/// Отметки принадлежат экземпляру поиска и не зависят от его выдачи.
///
/// Принятая команда выполняется до результата и без поиска: его уход передаёт
/// право предъявления оболочке.
final class RelationBatchViewModelProvider
    extends $NotifierProvider<RelationBatchViewModel, RelationBatchState> {
  /// Отметки принадлежат экземпляру поиска и не зависят от его выдачи.
  ///
  /// Принятая команда выполняется до результата и без поиска: его уход передаёт
  /// право предъявления оболочке.
  RelationBatchViewModelProvider._({
    required RelationBatchViewModelFamily super.from,
    required (
      IntentionSearchSession,
      IntentionId,
      IntentionRelationGroup,
      String,
    )
    super.argument,
  }) : super(
         retry: null,
         name: r'relationBatchViewModelProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$relationBatchViewModelHash();

  @override
  String toString() {
    return r'relationBatchViewModelProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  RelationBatchViewModel create() => RelationBatchViewModel();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(RelationBatchState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<RelationBatchState>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is RelationBatchViewModelProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$relationBatchViewModelHash() =>
    r'5393e016d02cf48f57c4dd980cf556f700ff12f4';

/// Отметки принадлежат экземпляру поиска и не зависят от его выдачи.
///
/// Принятая команда выполняется до результата и без поиска: его уход передаёт
/// право предъявления оболочке.

final class RelationBatchViewModelFamily extends $Family
    with
        $ClassFamilyOverride<
          RelationBatchViewModel,
          RelationBatchState,
          RelationBatchState,
          RelationBatchState,
          (IntentionSearchSession, IntentionId, IntentionRelationGroup, String)
        > {
  RelationBatchViewModelFamily._()
    : super(
        retry: null,
        name: r'relationBatchViewModelProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Отметки принадлежат экземпляру поиска и не зависят от его выдачи.
  ///
  /// Принятая команда выполняется до результата и без поиска: его уход передаёт
  /// право предъявления оболочке.

  RelationBatchViewModelProvider call(
    IntentionSearchSession session,
    IntentionId pageId,
    IntentionRelationGroup group,
    String pageTitle,
  ) => RelationBatchViewModelProvider._(
    argument: (session, pageId, group, pageTitle),
    from: this,
  );

  @override
  String toString() => r'relationBatchViewModelProvider';
}

/// Отметки принадлежат экземпляру поиска и не зависят от его выдачи.
///
/// Принятая команда выполняется до результата и без поиска: его уход передаёт
/// право предъявления оболочке.

abstract class _$RelationBatchViewModel extends $Notifier<RelationBatchState> {
  late final _$args =
      ref.$arg
          as (
            IntentionSearchSession,
            IntentionId,
            IntentionRelationGroup,
            String,
          );
  IntentionSearchSession get session => _$args.$1;
  IntentionId get pageId => _$args.$2;
  IntentionRelationGroup get group => _$args.$3;
  String get pageTitle => _$args.$4;

  RelationBatchState build(
    IntentionSearchSession session,
    IntentionId pageId,
    IntentionRelationGroup group,
    String pageTitle,
  );
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<RelationBatchState, RelationBatchState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<RelationBatchState, RelationBatchState>,
              RelationBatchState,
              Object?,
              Object?
            >;
    return element.handleCreate(
      ref,
      () => build(_$args.$1, _$args.$2, _$args.$3, _$args.$4),
    );
  }
}
