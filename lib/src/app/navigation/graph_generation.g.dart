// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'graph_generation.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Текущее поколение графа в контейнере приложения.
///
/// Завершение операции с изменением «граф заменён» начинает новое
/// поколение. Оболочка по нему создаёт корневые страницы заново, а их модели,
/// которые следят за поколением, задают начальное состояние, как при запуске
/// приложения. Поколение живёт весь контейнер: пересозданное поколение
/// сбросило бы страницы без замены графа.

@ProviderFor(CurrentGraphGeneration)
final currentGraphGenerationProvider = CurrentGraphGenerationProvider._();

/// Текущее поколение графа в контейнере приложения.
///
/// Завершение операции с изменением «граф заменён» начинает новое
/// поколение. Оболочка по нему создаёт корневые страницы заново, а их модели,
/// которые следят за поколением, задают начальное состояние, как при запуске
/// приложения. Поколение живёт весь контейнер: пересозданное поколение
/// сбросило бы страницы без замены графа.
final class CurrentGraphGenerationProvider
    extends $NotifierProvider<CurrentGraphGeneration, GraphGeneration> {
  /// Текущее поколение графа в контейнере приложения.
  ///
  /// Завершение операции с изменением «граф заменён» начинает новое
  /// поколение. Оболочка по нему создаёт корневые страницы заново, а их модели,
  /// которые следят за поколением, задают начальное состояние, как при запуске
  /// приложения. Поколение живёт весь контейнер: пересозданное поколение
  /// сбросило бы страницы без замены графа.
  CurrentGraphGenerationProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'currentGraphGenerationProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$currentGraphGenerationHash();

  @$internal
  @override
  CurrentGraphGeneration create() => CurrentGraphGeneration();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(GraphGeneration value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<GraphGeneration>(value),
    );
  }
}

String _$currentGraphGenerationHash() =>
    r'38f231ffe8f4c45e9e397fb2325aa84ff9b07836';

/// Текущее поколение графа в контейнере приложения.
///
/// Завершение операции с изменением «граф заменён» начинает новое
/// поколение. Оболочка по нему создаёт корневые страницы заново, а их модели,
/// которые следят за поколением, задают начальное состояние, как при запуске
/// приложения. Поколение живёт весь контейнер: пересозданное поколение
/// сбросило бы страницы без замены графа.

abstract class _$CurrentGraphGeneration extends $Notifier<GraphGeneration> {
  GraphGeneration build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<GraphGeneration, GraphGeneration>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<GraphGeneration, GraphGeneration>,
              GraphGeneration,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
