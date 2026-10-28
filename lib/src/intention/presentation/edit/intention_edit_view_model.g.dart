// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'intention_edit_view_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Экранная сессия изменения названия и описания намерения по ключу формы.
///
/// Сессия получает сохранённые тексты из подробных данных на момент открытия:
/// экран открывается только над полученными подробными данными, пока для
/// намерения не выполняется изменяющая команда, поэтому снимок не
/// согласуется с результатом ранее начатой операции.
///
/// Принятое сохранение удерживает координатор: освобождение сессии его не
/// отменяет, а поздний отказ переходит общей поверхности. Пока отказ
/// действует, сессия публикует право его предъявления; право, которое
/// состояние перестало публиковать, и право выполняющегося сохранения при
/// освобождении сессия передаёт общей поверхности.

@ProviderFor(IntentionEditViewModel)
final intentionEditViewModelProvider = IntentionEditViewModelFamily._();

/// Экранная сессия изменения названия и описания намерения по ключу формы.
///
/// Сессия получает сохранённые тексты из подробных данных на момент открытия:
/// экран открывается только над полученными подробными данными, пока для
/// намерения не выполняется изменяющая команда, поэтому снимок не
/// согласуется с результатом ранее начатой операции.
///
/// Принятое сохранение удерживает координатор: освобождение сессии его не
/// отменяет, а поздний отказ переходит общей поверхности. Пока отказ
/// действует, сессия публикует право его предъявления; право, которое
/// состояние перестало публиковать, и право выполняющегося сохранения при
/// освобождении сессия передаёт общей поверхности.
final class IntentionEditViewModelProvider
    extends $NotifierProvider<IntentionEditViewModel, IntentionEditState> {
  /// Экранная сессия изменения названия и описания намерения по ключу формы.
  ///
  /// Сессия получает сохранённые тексты из подробных данных на момент открытия:
  /// экран открывается только над полученными подробными данными, пока для
  /// намерения не выполняется изменяющая команда, поэтому снимок не
  /// согласуется с результатом ранее начатой операции.
  ///
  /// Принятое сохранение удерживает координатор: освобождение сессии его не
  /// отменяет, а поздний отказ переходит общей поверхности. Пока отказ
  /// действует, сессия публикует право его предъявления; право, которое
  /// состояние перестало публиковать, и право выполняющегося сохранения при
  /// освобождении сессия передаёт общей поверхности.
  IntentionEditViewModelProvider._({
    required IntentionEditViewModelFamily super.from,
    required (IntentionEditFormKey, IntentionId) super.argument,
  }) : super(
         retry: null,
         name: r'intentionEditViewModelProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$intentionEditViewModelHash();

  @override
  String toString() {
    return r'intentionEditViewModelProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  IntentionEditViewModel create() => IntentionEditViewModel();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(IntentionEditState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<IntentionEditState>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is IntentionEditViewModelProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$intentionEditViewModelHash() =>
    r'5ebab4b5a2a4271f8ca4dc2d17a911616bc874b3';

/// Экранная сессия изменения названия и описания намерения по ключу формы.
///
/// Сессия получает сохранённые тексты из подробных данных на момент открытия:
/// экран открывается только над полученными подробными данными, пока для
/// намерения не выполняется изменяющая команда, поэтому снимок не
/// согласуется с результатом ранее начатой операции.
///
/// Принятое сохранение удерживает координатор: освобождение сессии его не
/// отменяет, а поздний отказ переходит общей поверхности. Пока отказ
/// действует, сессия публикует право его предъявления; право, которое
/// состояние перестало публиковать, и право выполняющегося сохранения при
/// освобождении сессия передаёт общей поверхности.

final class IntentionEditViewModelFamily extends $Family
    with
        $ClassFamilyOverride<
          IntentionEditViewModel,
          IntentionEditState,
          IntentionEditState,
          IntentionEditState,
          (IntentionEditFormKey, IntentionId)
        > {
  IntentionEditViewModelFamily._()
    : super(
        retry: null,
        name: r'intentionEditViewModelProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Экранная сессия изменения названия и описания намерения по ключу формы.
  ///
  /// Сессия получает сохранённые тексты из подробных данных на момент открытия:
  /// экран открывается только над полученными подробными данными, пока для
  /// намерения не выполняется изменяющая команда, поэтому снимок не
  /// согласуется с результатом ранее начатой операции.
  ///
  /// Принятое сохранение удерживает координатор: освобождение сессии его не
  /// отменяет, а поздний отказ переходит общей поверхности. Пока отказ
  /// действует, сессия публикует право его предъявления; право, которое
  /// состояние перестало публиковать, и право выполняющегося сохранения при
  /// освобождении сессия передаёт общей поверхности.

  IntentionEditViewModelProvider call(
    IntentionEditFormKey formKey,
    IntentionId intentionId,
  ) => IntentionEditViewModelProvider._(
    argument: (formKey, intentionId),
    from: this,
  );

  @override
  String toString() => r'intentionEditViewModelProvider';
}

/// Экранная сессия изменения названия и описания намерения по ключу формы.
///
/// Сессия получает сохранённые тексты из подробных данных на момент открытия:
/// экран открывается только над полученными подробными данными, пока для
/// намерения не выполняется изменяющая команда, поэтому снимок не
/// согласуется с результатом ранее начатой операции.
///
/// Принятое сохранение удерживает координатор: освобождение сессии его не
/// отменяет, а поздний отказ переходит общей поверхности. Пока отказ
/// действует, сессия публикует право его предъявления; право, которое
/// состояние перестало публиковать, и право выполняющегося сохранения при
/// освобождении сессия передаёт общей поверхности.

abstract class _$IntentionEditViewModel extends $Notifier<IntentionEditState> {
  late final _$args = ref.$arg as (IntentionEditFormKey, IntentionId);
  IntentionEditFormKey get formKey => _$args.$1;
  IntentionId get intentionId => _$args.$2;

  IntentionEditState build(
    IntentionEditFormKey formKey,
    IntentionId intentionId,
  );
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<IntentionEditState, IntentionEditState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<IntentionEditState, IntentionEditState>,
              IntentionEditState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args.$1, _$args.$2));
  }
}
