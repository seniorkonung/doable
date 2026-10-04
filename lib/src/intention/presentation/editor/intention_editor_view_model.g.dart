// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'intention_editor_view_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Экранная сессия создания намерения по собственному ключу формы.
///
/// До отправки владеет черновиком: правки текста, набора тегов и обеих
/// отметок меняют только его и не отправляют команд графа. Отправка передаёт
/// координатору одну команду с неизменяемым снимком всех пяти полей и до
/// результата отвергает правки черновика и повторную отправку. Принятую
/// отправку удерживает координатор: освобождение сессии её не отменяет и не
/// снимает ограничение ключа формы. Сессия закрыта после успешного создания
/// или освобождения и отвергает правки черновика.

@ProviderFor(IntentionEditorViewModel)
final intentionEditorViewModelProvider = IntentionEditorViewModelFamily._();

/// Экранная сессия создания намерения по собственному ключу формы.
///
/// До отправки владеет черновиком: правки текста, набора тегов и обеих
/// отметок меняют только его и не отправляют команд графа. Отправка передаёт
/// координатору одну команду с неизменяемым снимком всех пяти полей и до
/// результата отвергает правки черновика и повторную отправку. Принятую
/// отправку удерживает координатор: освобождение сессии её не отменяет и не
/// снимает ограничение ключа формы. Сессия закрыта после успешного создания
/// или освобождения и отвергает правки черновика.
final class IntentionEditorViewModelProvider
    extends $NotifierProvider<IntentionEditorViewModel, IntentionEditorState> {
  /// Экранная сессия создания намерения по собственному ключу формы.
  ///
  /// До отправки владеет черновиком: правки текста, набора тегов и обеих
  /// отметок меняют только его и не отправляют команд графа. Отправка передаёт
  /// координатору одну команду с неизменяемым снимком всех пяти полей и до
  /// результата отвергает правки черновика и повторную отправку. Принятую
  /// отправку удерживает координатор: освобождение сессии её не отменяет и не
  /// снимает ограничение ключа формы. Сессия закрыта после успешного создания
  /// или освобождения и отвергает правки черновика.
  IntentionEditorViewModelProvider._({
    required IntentionEditorViewModelFamily super.from,
    required IntentionCreationFormKey super.argument,
  }) : super(
         retry: null,
         name: r'intentionEditorViewModelProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$intentionEditorViewModelHash();

  @override
  String toString() {
    return r'intentionEditorViewModelProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  IntentionEditorViewModel create() => IntentionEditorViewModel();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(IntentionEditorState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<IntentionEditorState>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is IntentionEditorViewModelProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$intentionEditorViewModelHash() =>
    r'133911f86db58fcb08014a2d21f48abcf39c051f';

/// Экранная сессия создания намерения по собственному ключу формы.
///
/// До отправки владеет черновиком: правки текста, набора тегов и обеих
/// отметок меняют только его и не отправляют команд графа. Отправка передаёт
/// координатору одну команду с неизменяемым снимком всех пяти полей и до
/// результата отвергает правки черновика и повторную отправку. Принятую
/// отправку удерживает координатор: освобождение сессии её не отменяет и не
/// снимает ограничение ключа формы. Сессия закрыта после успешного создания
/// или освобождения и отвергает правки черновика.

final class IntentionEditorViewModelFamily extends $Family
    with
        $ClassFamilyOverride<
          IntentionEditorViewModel,
          IntentionEditorState,
          IntentionEditorState,
          IntentionEditorState,
          IntentionCreationFormKey
        > {
  IntentionEditorViewModelFamily._()
    : super(
        retry: null,
        name: r'intentionEditorViewModelProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Экранная сессия создания намерения по собственному ключу формы.
  ///
  /// До отправки владеет черновиком: правки текста, набора тегов и обеих
  /// отметок меняют только его и не отправляют команд графа. Отправка передаёт
  /// координатору одну команду с неизменяемым снимком всех пяти полей и до
  /// результата отвергает правки черновика и повторную отправку. Принятую
  /// отправку удерживает координатор: освобождение сессии её не отменяет и не
  /// снимает ограничение ключа формы. Сессия закрыта после успешного создания
  /// или освобождения и отвергает правки черновика.

  IntentionEditorViewModelProvider call(IntentionCreationFormKey formKey) =>
      IntentionEditorViewModelProvider._(argument: formKey, from: this);

  @override
  String toString() => r'intentionEditorViewModelProvider';
}

/// Экранная сессия создания намерения по собственному ключу формы.
///
/// До отправки владеет черновиком: правки текста, набора тегов и обеих
/// отметок меняют только его и не отправляют команд графа. Отправка передаёт
/// координатору одну команду с неизменяемым снимком всех пяти полей и до
/// результата отвергает правки черновика и повторную отправку. Принятую
/// отправку удерживает координатор: освобождение сессии её не отменяет и не
/// снимает ограничение ключа формы. Сессия закрыта после успешного создания
/// или освобождения и отвергает правки черновика.

abstract class _$IntentionEditorViewModel
    extends $Notifier<IntentionEditorState> {
  late final _$args = ref.$arg as IntentionCreationFormKey;
  IntentionCreationFormKey get formKey => _$args;

  IntentionEditorState build(IntentionCreationFormKey formKey);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<IntentionEditorState, IntentionEditorState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<IntentionEditorState, IntentionEditorState>,
              IntentionEditorState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
