// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'intention_relations_view_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Порциями получает активные связи группы, выбранной экземпляром страницы,
/// и, пока архив группы раскрыт, её архивированные связи.
///
/// Модель живёт, пока её слушают: освобождение отбрасывает строки,
/// продолжения и подписки, а группа и раскрытие архивов остаются в
/// экземпляре страницы. Согласование с графом ведёт общий слой списков
/// страницы и публикует обе части на одной ревизии; модель задаёт чтение
/// частей группы, принадлежность строки и значимые для группы изменения.
// https://riverpod.dev/docs/concepts2/family
// https://riverpod.dev/docs/concepts2/auto_dispose

@ProviderFor(IntentionRelationsViewModel)
final intentionRelationsViewModelProvider =
    IntentionRelationsViewModelFamily._();

/// Порциями получает активные связи группы, выбранной экземпляром страницы,
/// и, пока архив группы раскрыт, её архивированные связи.
///
/// Модель живёт, пока её слушают: освобождение отбрасывает строки,
/// продолжения и подписки, а группа и раскрытие архивов остаются в
/// экземпляре страницы. Согласование с графом ведёт общий слой списков
/// страницы и публикует обе части на одной ревизии; модель задаёт чтение
/// частей группы, принадлежность строки и значимые для группы изменения.
// https://riverpod.dev/docs/concepts2/family
// https://riverpod.dev/docs/concepts2/auto_dispose
final class IntentionRelationsViewModelProvider
    extends
        $NotifierProvider<
          IntentionRelationsViewModel,
          IntentionRelationsState
        > {
  /// Порциями получает активные связи группы, выбранной экземпляром страницы,
  /// и, пока архив группы раскрыт, её архивированные связи.
  ///
  /// Модель живёт, пока её слушают: освобождение отбрасывает строки,
  /// продолжения и подписки, а группа и раскрытие архивов остаются в
  /// экземпляре страницы. Согласование с графом ведёт общий слой списков
  /// страницы и публикует обе части на одной ревизии; модель задаёт чтение
  /// частей группы, принадлежность строки и значимые для группы изменения.
  // https://riverpod.dev/docs/concepts2/family
  // https://riverpod.dev/docs/concepts2/auto_dispose
  IntentionRelationsViewModelProvider._({
    required IntentionRelationsViewModelFamily super.from,
    required (IntentionId, IntentionPageInstance) super.argument,
  }) : super(
         retry: null,
         name: r'intentionRelationsViewModelProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$intentionRelationsViewModelHash();

  @override
  String toString() {
    return r'intentionRelationsViewModelProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  IntentionRelationsViewModel create() => IntentionRelationsViewModel();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(IntentionRelationsState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<IntentionRelationsState>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is IntentionRelationsViewModelProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$intentionRelationsViewModelHash() =>
    r'57b3254443b5331b4d02f7368a087a4e07f32188';

/// Порциями получает активные связи группы, выбранной экземпляром страницы,
/// и, пока архив группы раскрыт, её архивированные связи.
///
/// Модель живёт, пока её слушают: освобождение отбрасывает строки,
/// продолжения и подписки, а группа и раскрытие архивов остаются в
/// экземпляре страницы. Согласование с графом ведёт общий слой списков
/// страницы и публикует обе части на одной ревизии; модель задаёт чтение
/// частей группы, принадлежность строки и значимые для группы изменения.
// https://riverpod.dev/docs/concepts2/family
// https://riverpod.dev/docs/concepts2/auto_dispose

final class IntentionRelationsViewModelFamily extends $Family
    with
        $ClassFamilyOverride<
          IntentionRelationsViewModel,
          IntentionRelationsState,
          IntentionRelationsState,
          IntentionRelationsState,
          (IntentionId, IntentionPageInstance)
        > {
  IntentionRelationsViewModelFamily._()
    : super(
        retry: null,
        name: r'intentionRelationsViewModelProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Порциями получает активные связи группы, выбранной экземпляром страницы,
  /// и, пока архив группы раскрыт, её архивированные связи.
  ///
  /// Модель живёт, пока её слушают: освобождение отбрасывает строки,
  /// продолжения и подписки, а группа и раскрытие архивов остаются в
  /// экземпляре страницы. Согласование с графом ведёт общий слой списков
  /// страницы и публикует обе части на одной ревизии; модель задаёт чтение
  /// частей группы, принадлежность строки и значимые для группы изменения.
  // https://riverpod.dev/docs/concepts2/family
  // https://riverpod.dev/docs/concepts2/auto_dispose

  IntentionRelationsViewModelProvider call(
    IntentionId intentionId,
    IntentionPageInstance pageInstance,
  ) => IntentionRelationsViewModelProvider._(
    argument: (intentionId, pageInstance),
    from: this,
  );

  @override
  String toString() => r'intentionRelationsViewModelProvider';
}

/// Порциями получает активные связи группы, выбранной экземпляром страницы,
/// и, пока архив группы раскрыт, её архивированные связи.
///
/// Модель живёт, пока её слушают: освобождение отбрасывает строки,
/// продолжения и подписки, а группа и раскрытие архивов остаются в
/// экземпляре страницы. Согласование с графом ведёт общий слой списков
/// страницы и публикует обе части на одной ревизии; модель задаёт чтение
/// частей группы, принадлежность строки и значимые для группы изменения.
// https://riverpod.dev/docs/concepts2/family
// https://riverpod.dev/docs/concepts2/auto_dispose

abstract class _$IntentionRelationsViewModel
    extends $Notifier<IntentionRelationsState> {
  late final _$args = ref.$arg as (IntentionId, IntentionPageInstance);
  IntentionId get intentionId => _$args.$1;
  IntentionPageInstance get pageInstance => _$args.$2;

  IntentionRelationsState build(
    IntentionId intentionId,
    IntentionPageInstance pageInstance,
  );
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<IntentionRelationsState, IntentionRelationsState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<IntentionRelationsState, IntentionRelationsState>,
              IntentionRelationsState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args.$1, _$args.$2));
  }
}
