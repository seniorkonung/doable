// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'intention_tag_conditions_view_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Выбранные условия по тегам одного назначения поиска.
///
/// Изменение условий сразу передаётся модели каталога того же назначения.
/// Модель не выполняет команд тегов и не читает выдачу: читается только
/// текущее состояние тега, выбранного из возможно устаревшего снимка.
/// Условия живут, пока открыт их поиск, и между открытиями не сохраняются.

@ProviderFor(IntentionTagConditionsViewModel)
final intentionTagConditionsViewModelProvider =
    IntentionTagConditionsViewModelFamily._();

/// Выбранные условия по тегам одного назначения поиска.
///
/// Изменение условий сразу передаётся модели каталога того же назначения.
/// Модель не выполняет команд тегов и не читает выдачу: читается только
/// текущее состояние тега, выбранного из возможно устаревшего снимка.
/// Условия живут, пока открыт их поиск, и между открытиями не сохраняются.
final class IntentionTagConditionsViewModelProvider
    extends
        $NotifierProvider<
          IntentionTagConditionsViewModel,
          IntentionTagConditionsState
        > {
  /// Выбранные условия по тегам одного назначения поиска.
  ///
  /// Изменение условий сразу передаётся модели каталога того же назначения.
  /// Модель не выполняет команд тегов и не читает выдачу: читается только
  /// текущее состояние тега, выбранного из возможно устаревшего снимка.
  /// Условия живут, пока открыт их поиск, и между открытиями не сохраняются.
  IntentionTagConditionsViewModelProvider._({
    required IntentionTagConditionsViewModelFamily super.from,
    required IntentionCatalogPurpose super.argument,
  }) : super(
         retry: null,
         name: r'intentionTagConditionsViewModelProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$intentionTagConditionsViewModelHash();

  @override
  String toString() {
    return r'intentionTagConditionsViewModelProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  IntentionTagConditionsViewModel create() => IntentionTagConditionsViewModel();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(IntentionTagConditionsState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<IntentionTagConditionsState>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is IntentionTagConditionsViewModelProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$intentionTagConditionsViewModelHash() =>
    r'ff4d6f94420bddc76d69bd0c1d9d31e59a7bcc5f';

/// Выбранные условия по тегам одного назначения поиска.
///
/// Изменение условий сразу передаётся модели каталога того же назначения.
/// Модель не выполняет команд тегов и не читает выдачу: читается только
/// текущее состояние тега, выбранного из возможно устаревшего снимка.
/// Условия живут, пока открыт их поиск, и между открытиями не сохраняются.

final class IntentionTagConditionsViewModelFamily extends $Family
    with
        $ClassFamilyOverride<
          IntentionTagConditionsViewModel,
          IntentionTagConditionsState,
          IntentionTagConditionsState,
          IntentionTagConditionsState,
          IntentionCatalogPurpose
        > {
  IntentionTagConditionsViewModelFamily._()
    : super(
        retry: null,
        name: r'intentionTagConditionsViewModelProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Выбранные условия по тегам одного назначения поиска.
  ///
  /// Изменение условий сразу передаётся модели каталога того же назначения.
  /// Модель не выполняет команд тегов и не читает выдачу: читается только
  /// текущее состояние тега, выбранного из возможно устаревшего снимка.
  /// Условия живут, пока открыт их поиск, и между открытиями не сохраняются.

  IntentionTagConditionsViewModelProvider call(
    IntentionCatalogPurpose purpose,
  ) => IntentionTagConditionsViewModelProvider._(argument: purpose, from: this);

  @override
  String toString() => r'intentionTagConditionsViewModelProvider';
}

/// Выбранные условия по тегам одного назначения поиска.
///
/// Изменение условий сразу передаётся модели каталога того же назначения.
/// Модель не выполняет команд тегов и не читает выдачу: читается только
/// текущее состояние тега, выбранного из возможно устаревшего снимка.
/// Условия живут, пока открыт их поиск, и между открытиями не сохраняются.

abstract class _$IntentionTagConditionsViewModel
    extends $Notifier<IntentionTagConditionsState> {
  late final _$args = ref.$arg as IntentionCatalogPurpose;
  IntentionCatalogPurpose get purpose => _$args;

  IntentionTagConditionsState build(IntentionCatalogPurpose purpose);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<IntentionTagConditionsState, IntentionTagConditionsState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                IntentionTagConditionsState,
                IntentionTagConditionsState
              >,
              IntentionTagConditionsState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
