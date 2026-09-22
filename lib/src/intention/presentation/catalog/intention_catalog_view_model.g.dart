// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'intention_catalog_view_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Ограниченный каталог намерений для одного назначения.
///
/// Назначение задаёт отдельное состояние просмотра: выбор участника связи и
/// открытый каталог намерений не разделяют охват, фильтр и загруженную часть.

@ProviderFor(IntentionCatalogViewModel)
final intentionCatalogViewModelProvider = IntentionCatalogViewModelFamily._();

/// Ограниченный каталог намерений для одного назначения.
///
/// Назначение задаёт отдельное состояние просмотра: выбор участника связи и
/// открытый каталог намерений не разделяют охват, фильтр и загруженную часть.
final class IntentionCatalogViewModelProvider
    extends
        $AsyncNotifierProvider<
          IntentionCatalogViewModel,
          IntentionCatalogState
        > {
  /// Ограниченный каталог намерений для одного назначения.
  ///
  /// Назначение задаёт отдельное состояние просмотра: выбор участника связи и
  /// открытый каталог намерений не разделяют охват, фильтр и загруженную часть.
  IntentionCatalogViewModelProvider._({
    required IntentionCatalogViewModelFamily super.from,
    required IntentionCatalogPurpose super.argument,
  }) : super(
         retry: null,
         name: r'intentionCatalogViewModelProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$intentionCatalogViewModelHash();

  @override
  String toString() {
    return r'intentionCatalogViewModelProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  IntentionCatalogViewModel create() => IntentionCatalogViewModel();

  @override
  bool operator ==(Object other) {
    return other is IntentionCatalogViewModelProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$intentionCatalogViewModelHash() =>
    r'e725ec48c1f53f40498a04762b1b6367cf7e85e1';

/// Ограниченный каталог намерений для одного назначения.
///
/// Назначение задаёт отдельное состояние просмотра: выбор участника связи и
/// открытый каталог намерений не разделяют охват, фильтр и загруженную часть.

final class IntentionCatalogViewModelFamily extends $Family
    with
        $ClassFamilyOverride<
          IntentionCatalogViewModel,
          AsyncValue<IntentionCatalogState>,
          IntentionCatalogState,
          FutureOr<IntentionCatalogState>,
          IntentionCatalogPurpose
        > {
  IntentionCatalogViewModelFamily._()
    : super(
        retry: null,
        name: r'intentionCatalogViewModelProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Ограниченный каталог намерений для одного назначения.
  ///
  /// Назначение задаёт отдельное состояние просмотра: выбор участника связи и
  /// открытый каталог намерений не разделяют охват, фильтр и загруженную часть.

  IntentionCatalogViewModelProvider call(IntentionCatalogPurpose purpose) =>
      IntentionCatalogViewModelProvider._(argument: purpose, from: this);

  @override
  String toString() => r'intentionCatalogViewModelProvider';
}

/// Ограниченный каталог намерений для одного назначения.
///
/// Назначение задаёт отдельное состояние просмотра: выбор участника связи и
/// открытый каталог намерений не разделяют охват, фильтр и загруженную часть.

abstract class _$IntentionCatalogViewModel
    extends $AsyncNotifier<IntentionCatalogState> {
  late final _$args = ref.$arg as IntentionCatalogPurpose;
  IntentionCatalogPurpose get purpose => _$args;

  FutureOr<IntentionCatalogState> build(IntentionCatalogPurpose purpose);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<AsyncValue<IntentionCatalogState>, IntentionCatalogState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AsyncValue<IntentionCatalogState>,
                IntentionCatalogState
              >,
              AsyncValue<IntentionCatalogState>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
