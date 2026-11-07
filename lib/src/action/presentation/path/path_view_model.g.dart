// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'path_view_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Сессия построения пути и порционного чтения его продолжений.
///
/// Для существующего действия сессия сама заменяет его путь. Замена
/// завершается и после ухода с экрана: тогда её отказ предъявляет общая
/// поверхность результатов, а успех виден в данных без сообщения.

@ProviderFor(PathViewModel)
final pathViewModelProvider = PathViewModelFamily._();

/// Сессия построения пути и порционного чтения его продолжений.
///
/// Для существующего действия сессия сама заменяет его путь. Замена
/// завершается и после ухода с экрана: тогда её отказ предъявляет общая
/// поверхность результатов, а успех виден в данных без сообщения.
final class PathViewModelProvider
    extends $NotifierProvider<PathViewModel, PathState> {
  /// Сессия построения пути и порционного чтения его продолжений.
  ///
  /// Для существующего действия сессия сама заменяет его путь. Замена
  /// завершается и после ухода с экрана: тогда её отказ предъявляет общая
  /// поверхность результатов, а успех виден в данных без сообщения.
  PathViewModelProvider._({
    required PathViewModelFamily super.from,
    required (PathSessionKey, PathPurpose) super.argument,
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

String _$pathViewModelHash() => r'97d08554671003fd7e75b29affa873bc8e778789';

/// Сессия построения пути и порционного чтения его продолжений.
///
/// Для существующего действия сессия сама заменяет его путь. Замена
/// завершается и после ухода с экрана: тогда её отказ предъявляет общая
/// поверхность результатов, а успех виден в данных без сообщения.

final class PathViewModelFamily extends $Family
    with
        $ClassFamilyOverride<
          PathViewModel,
          PathState,
          PathState,
          PathState,
          (PathSessionKey, PathPurpose)
        > {
  PathViewModelFamily._()
    : super(
        retry: null,
        name: r'pathViewModelProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Сессия построения пути и порционного чтения его продолжений.
  ///
  /// Для существующего действия сессия сама заменяет его путь. Замена
  /// завершается и после ухода с экрана: тогда её отказ предъявляет общая
  /// поверхность результатов, а успех виден в данных без сообщения.

  PathViewModelProvider call(PathSessionKey sessionKey, PathPurpose purpose) =>
      PathViewModelProvider._(argument: (sessionKey, purpose), from: this);

  @override
  String toString() => r'pathViewModelProvider';
}

/// Сессия построения пути и порционного чтения его продолжений.
///
/// Для существующего действия сессия сама заменяет его путь. Замена
/// завершается и после ухода с экрана: тогда её отказ предъявляет общая
/// поверхность результатов, а успех виден в данных без сообщения.

abstract class _$PathViewModel extends $Notifier<PathState> {
  late final _$args = ref.$arg as (PathSessionKey, PathPurpose);
  PathSessionKey get sessionKey => _$args.$1;
  PathPurpose get purpose => _$args.$2;

  PathState build(PathSessionKey sessionKey, PathPurpose purpose);
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
