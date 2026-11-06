// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'intention_actions_view_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Числа ролей и порции действий намерения, в путях которых оно играет
/// выбранную роль.
///
/// Страница держит модель, пока подробные данные намерения получены, поэтому
/// число вкладки известно и под другими вкладками. Пока вкладка не показана
/// ([setVisible]), модель читает только числа и не держит строк и
/// продолжения. Выбранная плитка остаётся в экземпляре страницы.
///
/// Подтверждённые изменения действий пути намерения и корневых намерений
/// загруженных строк пересобирают числа и загруженную часть на одной
/// ревизии, а прежняя часть остаётся на экране до готовности замены.
// https://riverpod.dev/docs/concepts2/family
// https://riverpod.dev/docs/concepts2/auto_dispose

@ProviderFor(IntentionActionsViewModel)
final intentionActionsViewModelProvider = IntentionActionsViewModelFamily._();

/// Числа ролей и порции действий намерения, в путях которых оно играет
/// выбранную роль.
///
/// Страница держит модель, пока подробные данные намерения получены, поэтому
/// число вкладки известно и под другими вкладками. Пока вкладка не показана
/// ([setVisible]), модель читает только числа и не держит строк и
/// продолжения. Выбранная плитка остаётся в экземпляре страницы.
///
/// Подтверждённые изменения действий пути намерения и корневых намерений
/// загруженных строк пересобирают числа и загруженную часть на одной
/// ревизии, а прежняя часть остаётся на экране до готовности замены.
// https://riverpod.dev/docs/concepts2/family
// https://riverpod.dev/docs/concepts2/auto_dispose
final class IntentionActionsViewModelProvider
    extends
        $NotifierProvider<IntentionActionsViewModel, IntentionActionsState> {
  /// Числа ролей и порции действий намерения, в путях которых оно играет
  /// выбранную роль.
  ///
  /// Страница держит модель, пока подробные данные намерения получены, поэтому
  /// число вкладки известно и под другими вкладками. Пока вкладка не показана
  /// ([setVisible]), модель читает только числа и не держит строк и
  /// продолжения. Выбранная плитка остаётся в экземпляре страницы.
  ///
  /// Подтверждённые изменения действий пути намерения и корневых намерений
  /// загруженных строк пересобирают числа и загруженную часть на одной
  /// ревизии, а прежняя часть остаётся на экране до готовности замены.
  // https://riverpod.dev/docs/concepts2/family
  // https://riverpod.dev/docs/concepts2/auto_dispose
  IntentionActionsViewModelProvider._({
    required IntentionActionsViewModelFamily super.from,
    required (IntentionId, IntentionPageInstance) super.argument,
  }) : super(
         retry: null,
         name: r'intentionActionsViewModelProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$intentionActionsViewModelHash();

  @override
  String toString() {
    return r'intentionActionsViewModelProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  IntentionActionsViewModel create() => IntentionActionsViewModel();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(IntentionActionsState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<IntentionActionsState>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is IntentionActionsViewModelProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$intentionActionsViewModelHash() =>
    r'5bcb74e035b37da1c688af7979ae263264386274';

/// Числа ролей и порции действий намерения, в путях которых оно играет
/// выбранную роль.
///
/// Страница держит модель, пока подробные данные намерения получены, поэтому
/// число вкладки известно и под другими вкладками. Пока вкладка не показана
/// ([setVisible]), модель читает только числа и не держит строк и
/// продолжения. Выбранная плитка остаётся в экземпляре страницы.
///
/// Подтверждённые изменения действий пути намерения и корневых намерений
/// загруженных строк пересобирают числа и загруженную часть на одной
/// ревизии, а прежняя часть остаётся на экране до готовности замены.
// https://riverpod.dev/docs/concepts2/family
// https://riverpod.dev/docs/concepts2/auto_dispose

final class IntentionActionsViewModelFamily extends $Family
    with
        $ClassFamilyOverride<
          IntentionActionsViewModel,
          IntentionActionsState,
          IntentionActionsState,
          IntentionActionsState,
          (IntentionId, IntentionPageInstance)
        > {
  IntentionActionsViewModelFamily._()
    : super(
        retry: null,
        name: r'intentionActionsViewModelProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Числа ролей и порции действий намерения, в путях которых оно играет
  /// выбранную роль.
  ///
  /// Страница держит модель, пока подробные данные намерения получены, поэтому
  /// число вкладки известно и под другими вкладками. Пока вкладка не показана
  /// ([setVisible]), модель читает только числа и не держит строк и
  /// продолжения. Выбранная плитка остаётся в экземпляре страницы.
  ///
  /// Подтверждённые изменения действий пути намерения и корневых намерений
  /// загруженных строк пересобирают числа и загруженную часть на одной
  /// ревизии, а прежняя часть остаётся на экране до готовности замены.
  // https://riverpod.dev/docs/concepts2/family
  // https://riverpod.dev/docs/concepts2/auto_dispose

  IntentionActionsViewModelProvider call(
    IntentionId intentionId,
    IntentionPageInstance pageInstance,
  ) => IntentionActionsViewModelProvider._(
    argument: (intentionId, pageInstance),
    from: this,
  );

  @override
  String toString() => r'intentionActionsViewModelProvider';
}

/// Числа ролей и порции действий намерения, в путях которых оно играет
/// выбранную роль.
///
/// Страница держит модель, пока подробные данные намерения получены, поэтому
/// число вкладки известно и под другими вкладками. Пока вкладка не показана
/// ([setVisible]), модель читает только числа и не держит строк и
/// продолжения. Выбранная плитка остаётся в экземпляре страницы.
///
/// Подтверждённые изменения действий пути намерения и корневых намерений
/// загруженных строк пересобирают числа и загруженную часть на одной
/// ревизии, а прежняя часть остаётся на экране до готовности замены.
// https://riverpod.dev/docs/concepts2/family
// https://riverpod.dev/docs/concepts2/auto_dispose

abstract class _$IntentionActionsViewModel
    extends $Notifier<IntentionActionsState> {
  late final _$args = ref.$arg as (IntentionId, IntentionPageInstance);
  IntentionId get intentionId => _$args.$1;
  IntentionPageInstance get pageInstance => _$args.$2;

  IntentionActionsState build(
    IntentionId intentionId,
    IntentionPageInstance pageInstance,
  );
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<IntentionActionsState, IntentionActionsState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<IntentionActionsState, IntentionActionsState>,
              IntentionActionsState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args.$1, _$args.$2));
  }
}
