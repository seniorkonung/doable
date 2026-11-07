// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'path_view_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Экранная сессия пути по ключу экрана.
///
/// Путь на экране показывается по целому начальному участку, прочитанному
/// по последовательности намерений: участок короче последовательности
/// становится путём на экране. Смена корня и сокращение меняют только путь
/// на экране; граф остаётся прежним.

@ProviderFor(PathViewModel)
final pathViewModelProvider = PathViewModelFamily._();

/// Экранная сессия пути по ключу экрана.
///
/// Путь на экране показывается по целому начальному участку, прочитанному
/// по последовательности намерений: участок короче последовательности
/// становится путём на экране. Смена корня и сокращение меняют только путь
/// на экране; граф остаётся прежним.
final class PathViewModelProvider
    extends $NotifierProvider<PathViewModel, PathState> {
  /// Экранная сессия пути по ключу экрана.
  ///
  /// Путь на экране показывается по целому начальному участку, прочитанному
  /// по последовательности намерений: участок короче последовательности
  /// становится путём на экране. Смена корня и сокращение меняют только путь
  /// на экране; граф остаётся прежним.
  PathViewModelProvider._({
    required PathViewModelFamily super.from,
    required (PathSessionKey, ActionPath?) super.argument,
  }) : super(
         retry: null,
         name: r'pathViewModelProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$pathViewModelHash();

  @override
  String toString() {
    return r'pathViewModelProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  PathViewModel create() => PathViewModel();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(PathState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<PathState>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is PathViewModelProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$pathViewModelHash() => r'f4aa0cfdce5757ba8bb3a8a0819ea4cfe893226b';

/// Экранная сессия пути по ключу экрана.
///
/// Путь на экране показывается по целому начальному участку, прочитанному
/// по последовательности намерений: участок короче последовательности
/// становится путём на экране. Смена корня и сокращение меняют только путь
/// на экране; граф остаётся прежним.

final class PathViewModelFamily extends $Family
    with
        $ClassFamilyOverride<
          PathViewModel,
          PathState,
          PathState,
          PathState,
          (PathSessionKey, ActionPath?)
        > {
  PathViewModelFamily._()
    : super(
        retry: null,
        name: r'pathViewModelProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Экранная сессия пути по ключу экрана.
  ///
  /// Путь на экране показывается по целому начальному участку, прочитанному
  /// по последовательности намерений: участок короче последовательности
  /// становится путём на экране. Смена корня и сокращение меняют только путь
  /// на экране; граф остаётся прежним.

  PathViewModelProvider call(PathSessionKey sessionKey, ActionPath? original) =>
      PathViewModelProvider._(argument: (sessionKey, original), from: this);

  @override
  String toString() => r'pathViewModelProvider';
}

/// Экранная сессия пути по ключу экрана.
///
/// Путь на экране показывается по целому начальному участку, прочитанному
/// по последовательности намерений: участок короче последовательности
/// становится путём на экране. Смена корня и сокращение меняют только путь
/// на экране; граф остаётся прежним.

abstract class _$PathViewModel extends $Notifier<PathState> {
  late final _$args = ref.$arg as (PathSessionKey, ActionPath?);
  PathSessionKey get sessionKey => _$args.$1;
  ActionPath? get original => _$args.$2;

  PathState build(PathSessionKey sessionKey, ActionPath? original);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<PathState, PathState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<PathState, PathState>,
              PathState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args.$1, _$args.$2));
  }
}
