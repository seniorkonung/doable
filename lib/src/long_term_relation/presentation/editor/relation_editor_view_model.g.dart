// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'relation_editor_view_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Черновик одной формы создания или изменения долговременной связи.
///
/// ViewModel не хранит связь: он собирает выбор пользователя, проверяет его до
/// отправки и передаёт готовую команду общему coordinator графа. Пока принятая
/// отправка выполняется, вторая команда той же формы не принимается, а уход с
/// экрана завершает только экранную сессию — выполнение продолжается до
/// различимого результата.

@ProviderFor(RelationEditorViewModel)
final relationEditorViewModelProvider = RelationEditorViewModelFamily._();

/// Черновик одной формы создания или изменения долговременной связи.
///
/// ViewModel не хранит связь: он собирает выбор пользователя, проверяет его до
/// отправки и передаёт готовую команду общему coordinator графа. Пока принятая
/// отправка выполняется, вторая команда той же формы не принимается, а уход с
/// экрана завершает только экранную сессию — выполнение продолжается до
/// различимого результата.
final class RelationEditorViewModelProvider
    extends $NotifierProvider<RelationEditorViewModel, RelationEditorState> {
  /// Черновик одной формы создания или изменения долговременной связи.
  ///
  /// ViewModel не хранит связь: он собирает выбор пользователя, проверяет его до
  /// отправки и передаёт готовую команду общему coordinator графа. Пока принятая
  /// отправка выполняется, вторая команда той же формы не принимается, а уход с
  /// экрана завершает только экранную сессию — выполнение продолжается до
  /// различимого результата.
  RelationEditorViewModelProvider._({
    required RelationEditorViewModelFamily super.from,
    required (LongTermRelationCreationFormKey, RelationEditorContext)
    super.argument,
  }) : super(
         retry: null,
         name: r'relationEditorViewModelProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$relationEditorViewModelHash();

  @override
  String toString() {
    return r'relationEditorViewModelProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  RelationEditorViewModel create() => RelationEditorViewModel();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(RelationEditorState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<RelationEditorState>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is RelationEditorViewModelProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$relationEditorViewModelHash() =>
    r'b318b3249d56204eacf7f7d64b916899b9e45b4d';

/// Черновик одной формы создания или изменения долговременной связи.
///
/// ViewModel не хранит связь: он собирает выбор пользователя, проверяет его до
/// отправки и передаёт готовую команду общему coordinator графа. Пока принятая
/// отправка выполняется, вторая команда той же формы не принимается, а уход с
/// экрана завершает только экранную сессию — выполнение продолжается до
/// различимого результата.

final class RelationEditorViewModelFamily extends $Family
    with
        $ClassFamilyOverride<
          RelationEditorViewModel,
          RelationEditorState,
          RelationEditorState,
          RelationEditorState,
          (LongTermRelationCreationFormKey, RelationEditorContext)
        > {
  RelationEditorViewModelFamily._()
    : super(
        retry: null,
        name: r'relationEditorViewModelProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Черновик одной формы создания или изменения долговременной связи.
  ///
  /// ViewModel не хранит связь: он собирает выбор пользователя, проверяет его до
  /// отправки и передаёт готовую команду общему coordinator графа. Пока принятая
  /// отправка выполняется, вторая команда той же формы не принимается, а уход с
  /// экрана завершает только экранную сессию — выполнение продолжается до
  /// различимого результата.

  RelationEditorViewModelProvider call(
    LongTermRelationCreationFormKey formKey,
    RelationEditorContext context,
  ) => RelationEditorViewModelProvider._(
    argument: (formKey, context),
    from: this,
  );

  @override
  String toString() => r'relationEditorViewModelProvider';
}

/// Черновик одной формы создания или изменения долговременной связи.
///
/// ViewModel не хранит связь: он собирает выбор пользователя, проверяет его до
/// отправки и передаёт готовую команду общему coordinator графа. Пока принятая
/// отправка выполняется, вторая команда той же формы не принимается, а уход с
/// экрана завершает только экранную сессию — выполнение продолжается до
/// различимого результата.

abstract class _$RelationEditorViewModel
    extends $Notifier<RelationEditorState> {
  late final _$args =
      ref.$arg as (LongTermRelationCreationFormKey, RelationEditorContext);
  LongTermRelationCreationFormKey get formKey => _$args.$1;
  RelationEditorContext get context => _$args.$2;

  RelationEditorState build(
    LongTermRelationCreationFormKey formKey,
    RelationEditorContext context,
  );
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<RelationEditorState, RelationEditorState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<RelationEditorState, RelationEditorState>,
              RelationEditorState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args.$1, _$args.$2));
  }
}
