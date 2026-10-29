// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'intention_choices_view_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Порциями получает прямые дневные выборы намерения в роли, сохранённой
/// экземпляром страницы.
///
/// Модель живёт, пока её слушают: освобождение отбрасывает строки,
/// продолжения и подписки, а роль остаётся в экземпляре страницы.
/// Согласование с графом ведёт общий слой списков страницы; модель задаёт
/// чтение роли, принадлежность строки и значимые для роли изменения.
// https://riverpod.dev/docs/concepts2/family
// https://riverpod.dev/docs/concepts2/auto_dispose

@ProviderFor(IntentionChoicesViewModel)
final intentionChoicesViewModelProvider = IntentionChoicesViewModelFamily._();

/// Порциями получает прямые дневные выборы намерения в роли, сохранённой
/// экземпляром страницы.
///
/// Модель живёт, пока её слушают: освобождение отбрасывает строки,
/// продолжения и подписки, а роль остаётся в экземпляре страницы.
/// Согласование с графом ведёт общий слой списков страницы; модель задаёт
/// чтение роли, принадлежность строки и значимые для роли изменения.
// https://riverpod.dev/docs/concepts2/family
// https://riverpod.dev/docs/concepts2/auto_dispose
final class IntentionChoicesViewModelProvider
    extends
        $NotifierProvider<IntentionChoicesViewModel, IntentionChoicesState> {
  /// Порциями получает прямые дневные выборы намерения в роли, сохранённой
  /// экземпляром страницы.
  ///
  /// Модель живёт, пока её слушают: освобождение отбрасывает строки,
  /// продолжения и подписки, а роль остаётся в экземпляре страницы.
  /// Согласование с графом ведёт общий слой списков страницы; модель задаёт
  /// чтение роли, принадлежность строки и значимые для роли изменения.
  // https://riverpod.dev/docs/concepts2/family
  // https://riverpod.dev/docs/concepts2/auto_dispose
  IntentionChoicesViewModelProvider._({
    required IntentionChoicesViewModelFamily super.from,
    required (IntentionId, IntentionPageInstance) super.argument,
  }) : super(
         retry: null,
         name: r'intentionChoicesViewModelProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$intentionChoicesViewModelHash();

  @override
  String toString() {
    return r'intentionChoicesViewModelProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  IntentionChoicesViewModel create() => IntentionChoicesViewModel();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(IntentionChoicesState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<IntentionChoicesState>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is IntentionChoicesViewModelProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$intentionChoicesViewModelHash() =>
    r'b0957440a6d6dea35fea4fe26849ad27c5cf8f77';

/// Порциями получает прямые дневные выборы намерения в роли, сохранённой
/// экземпляром страницы.
///
/// Модель живёт, пока её слушают: освобождение отбрасывает строки,
/// продолжения и подписки, а роль остаётся в экземпляре страницы.
/// Согласование с графом ведёт общий слой списков страницы; модель задаёт
/// чтение роли, принадлежность строки и значимые для роли изменения.
// https://riverpod.dev/docs/concepts2/family
// https://riverpod.dev/docs/concepts2/auto_dispose

final class IntentionChoicesViewModelFamily extends $Family
    with
        $ClassFamilyOverride<
          IntentionChoicesViewModel,
          IntentionChoicesState,
          IntentionChoicesState,
          IntentionChoicesState,
          (IntentionId, IntentionPageInstance)
        > {
  IntentionChoicesViewModelFamily._()
    : super(
        retry: null,
        name: r'intentionChoicesViewModelProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Порциями получает прямые дневные выборы намерения в роли, сохранённой
  /// экземпляром страницы.
  ///
  /// Модель живёт, пока её слушают: освобождение отбрасывает строки,
  /// продолжения и подписки, а роль остаётся в экземпляре страницы.
  /// Согласование с графом ведёт общий слой списков страницы; модель задаёт
  /// чтение роли, принадлежность строки и значимые для роли изменения.
  // https://riverpod.dev/docs/concepts2/family
  // https://riverpod.dev/docs/concepts2/auto_dispose

  IntentionChoicesViewModelProvider call(
    IntentionId intentionId,
    IntentionPageInstance pageInstance,
  ) => IntentionChoicesViewModelProvider._(
    argument: (intentionId, pageInstance),
    from: this,
  );

  @override
  String toString() => r'intentionChoicesViewModelProvider';
}

/// Порциями получает прямые дневные выборы намерения в роли, сохранённой
/// экземпляром страницы.
///
/// Модель живёт, пока её слушают: освобождение отбрасывает строки,
/// продолжения и подписки, а роль остаётся в экземпляре страницы.
/// Согласование с графом ведёт общий слой списков страницы; модель задаёт
/// чтение роли, принадлежность строки и значимые для роли изменения.
// https://riverpod.dev/docs/concepts2/family
// https://riverpod.dev/docs/concepts2/auto_dispose

abstract class _$IntentionChoicesViewModel
    extends $Notifier<IntentionChoicesState> {
  late final _$args = ref.$arg as (IntentionId, IntentionPageInstance);
  IntentionId get intentionId => _$args.$1;
  IntentionPageInstance get pageInstance => _$args.$2;

  IntentionChoicesState build(
    IntentionId intentionId,
    IntentionPageInstance pageInstance,
  );
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<IntentionChoicesState, IntentionChoicesState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<IntentionChoicesState, IntentionChoicesState>,
              IntentionChoicesState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args.$1, _$args.$2));
  }
}
