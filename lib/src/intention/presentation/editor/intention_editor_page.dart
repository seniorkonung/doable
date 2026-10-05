import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../app/routing/app_router.gr.dart';
import '../../../graph/application/graph_command_coordinator.dart';
import '../../../graph/presentation/operation_failure_presentation.dart';
import '../../../tag/presentation/catalog/tag_selection_context.dart';
import '../../application/intention_result.dart';
import '../../domain/intention.dart';
import '../../domain/intention_text.dart';
import '../operation/operation_state.dart';
import 'intention_creation_sheet.dart';
import 'intention_creation_tags.dart';
import 'intention_editor_state.dart';
import 'intention_editor_view_model.dart';

/// Хост сессии создания намерения в модальной нижней панели над исходным
/// каталогом. Панель открывается компактной; человек явно разворачивает и
/// сворачивает ту же панель, а режим размера хранит сессия.
///
/// Теги черновика выбираются общим выбором тегов: хост открывает
/// существующий маршрут выбора с контекстом набора своей сессии полноэкранно
/// над панелью в том же корневом стеке. Маршрут панели остаётся под выбором
/// и редактором тега и удерживает сессию; закрытие выбора возвращает ту же
/// панель с её вводом, режимом и прокруткой. Выбранные теги показываются с
/// актуальностью из проекции сессии. Отказ сохранения из-за удалённых тегов
/// сохраняет набор: панель отмечает эти теги и предлагает явное исправление,
/// которое снимает только их и само сохранение не отправляет.
///
/// Ошибка поля показывается под своим полем: после отказа панель доводит
/// поле и текст ошибки до видимости и удерживает их видимыми, пока человек
/// не прокрутит панель или не изменит черновик. Общий отказ, исправление
/// набора тегов и допустимый повтор закреплены рядом с сохранением и видны
/// при любой прокрутке полей.
///
/// Сообщения общей поверхности приложения — успех создания, результаты
/// других экранов и ошибка, которую форма не предъявила до ухода, — видны
/// поверх полей панели над закреплённой областью. Пока форма жива, право её
/// ошибки остаётся у неё и при временном перекрытии выбором тегов,
/// редактором или диалогом.
///
/// Любой уход с формы — кнопка закрытия, нажатие вне панели, системное
/// «назад» и программный `maybePop` — сначала обращается к единому решению
/// сессии о закрытии и не удаляет маршрут сам. Маршрут формы закрывается
/// только по завершению сессии: сразу для неизменённого черновика, после
/// подтверждённого сброса или успешного создания.
@RoutePage()
final class IntentionEditorPage extends ConsumerStatefulWidget {
  const IntentionEditorPage({super.key});

  @override
  ConsumerState<IntentionEditorPage> createState() =>
      _IntentionEditorPageState();
}

final class _IntentionEditorPageState
    extends ConsumerState<IntentionEditorPage> {
  final _formKey = IntentionCreationFormKey();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();

  /// Поля, которые панель доводит до видимости вместе с их ошибкой.
  final _titleField = GlobalKey(debugLabel: 'intention-editor-title');
  final _descriptionField = GlobalKey(
    debugLabel: 'intention-editor-description',
  );

  /// Запрос держать видимым поле с текущей ошибкой. Действует, пока отказ и
  /// черновик остаются прежними.
  IntentionCreationSheetReveal? _failureReveal;

  /// Маршрут формы уже закрывается после завершения сессии.
  var _isRouteClosing = false;

  /// Объяснение критериев действия уже открыто.
  var _isConfirmingReadiness = false;

  /// Общий выбор тегов этой сессии уже открыт.
  var _isChoosingTags = false;

  IntentionEditorViewModelProvider get _provider =>
      intentionEditorViewModelProvider(_formKey);

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final provider = _provider;
    final editor = ref.watch(provider);
    final notifier = ref.read(provider.notifier);
    ref.listen(provider, (previous, next) {
      // Страница следит за сессией и перестраивается с новым запросом.
      _failureReveal = _failureRevealAfter(previous, next);
      if (next.event case IntentionEditorCreated()) {
        notifier.consumeEvent();
        // Сообщение об успехе предъявляет общий presenter оболочки.
        _closeRoute();
      }
    });

    // Во время отправки черновик зафиксирован: поля не должны показывать
    // текст, которого нет в принятой команде.
    final isDraftFixed = switch (editor.draftAvailability) {
      IntentionDraftAvailability.editable => false,
      IntentionDraftAvailability.submitting ||
      IntentionDraftAvailability.closed => true,
    };
    final failure = switch (editor.operation) {
      OperationFailed<Intention>(:final failure) => (
        place: _failurePlace(failure),
        message: _failureMessage(localizations, failure),
      ),
      OperationIdle<Intention>() ||
      OperationRunning<Intention>() ||
      OperationSucceeded<Intention>() => null,
    };
    String? failureAt(_FailurePlace place) =>
        failure?.place == place ? failure?.message : null;
    final titleFailure = failureAt(_FailurePlace.title);
    final descriptionFailure = failureAt(_FailurePlace.description);
    final pinnedFailure = failureAt(_FailurePlace.pinned);
    final missingTagIds = editor.missingTagIds;
    return PopScope<Object?>(
      // Маршрут не закрывается сам: решение принимает сессия.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          unawaited(_requestClose());
        }
      },
      child: IntentionCreationSheet(
        // Размер панели — режим этой сессии: смена режима не меняет черновик
        // и не запрашивает закрытие.
        mode: editor.sheetMode,
        onExpand: notifier.expandSheet,
        onCollapse: notifier.collapseSheet,
        closeLabel: localizations.editorCloseFormAction,
        expandLabel: localizations.editorExpandFormAction,
        collapseLabel: localizations.editorCollapseFormAction,
        onCloseRequested: () => unawaited(_requestClose()),
        reveal: _failureReveal,
        header: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Semantics(
            container: true,
            header: true,
            namesRoute: true,
            child: Text(
              localizations.editorTitle,
              key: const ValueKey('intention-editor-heading'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
        ),
        fields: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              KeyedSubtree(
                key: _titleField,
                child: TextField(
                  key: const ValueKey('intention-editor-title'),
                  controller: _titleController,
                  readOnly: isDraftFixed,
                  autofocus: true,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: localizations.editorTitleLabel,
                    error: titleFailure == null
                        ? null
                        : OperationFailurePresentation(
                            claim: editor.failurePresentation,
                            message: titleFailure,
                          ),
                  ),
                  onChanged: notifier.changeTitle,
                ),
              ),
              const SizedBox(height: 12),
              // Описание начинается одной строкой и растёт с текстом; то, что
              // не помещается в панель, доступно прокруткой полей.
              KeyedSubtree(
                key: _descriptionField,
                child: TextField(
                  key: const ValueKey('intention-editor-description'),
                  controller: _descriptionController,
                  readOnly: isDraftFixed,
                  minLines: 1,
                  maxLines: null,
                  keyboardType: TextInputType.multiline,
                  decoration: InputDecoration(
                    labelText: localizations.editorDescriptionLabel,
                    error: descriptionFailure == null
                        ? null
                        : OperationFailurePresentation(
                            claim: editor.failurePresentation,
                            message: descriptionFailure,
                          ),
                  ),
                  onChanged: notifier.changeDescription,
                ),
              ),
              if (editor.selectedTags.isNotEmpty) ...[
                const SizedBox(height: 12),
                IntentionCreationTags(
                  tags: editor.selectedTags,
                  missingTagIds: missingTagIds,
                  enabled: !isDraftFixed,
                  onRemove: notifier.removeTag,
                  onRetryObservation: notifier.retryTagObservation,
                ),
              ],
              const SizedBox(height: 8),
              _DraftOptions(
                favoriteMark: editor.draft.favoriteMark,
                readiness: editor.draft.readiness,
                enabled: !isDraftFixed,
                onChooseTags: () => unawaited(_chooseTags()),
                onMarkFavorite: notifier.markFavorite,
                onUnmarkFavorite: notifier.unmarkFavorite,
                onEnableReadiness: () => unawaited(_confirmReadiness()),
                onDisableReadiness: notifier.disableReadiness,
              ),
            ],
          ),
        ),
        status: pinnedFailure == null
            ? null
            : Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
                child: OperationFailurePresentation(
                  claim: editor.failurePresentation,
                  message: pinnedFailure,
                  messageKey: const ValueKey('intention-editor-failure'),
                ),
              ),
        // Исправление набора и повтор стоят вместе с сохранением и при
        // нехватке ширины переносятся друг под друга.
        footer: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
          child: OverflowBar(
            alignment: MainAxisAlignment.end,
            overflowAlignment: OverflowBarAlignment.end,
            spacing: 8,
            overflowSpacing: 8,
            children: [
              if (missingTagIds.isNotEmpty)
                // Исправление снимает только теги, отсутствие которых
                // подтвердил отказ, и не отправляет сохранение. Как и снятие
                // отдельного тега, оно не уводит фокус из поля ввода.
                TextFieldTapRegion(
                  child: OutlinedButton(
                    key: const ValueKey('intention-editor-remove-missing-tags'),
                    onPressed: isDraftFixed
                        ? null
                        : () => missingTagIds.forEach(notifier.removeTag),
                    child: Text(
                      localizations.editorRemoveMissingTags(
                        missingTagIds.length,
                      ),
                    ),
                  ),
                ),
              FilledButton(
                key: const ValueKey('intention-editor-submit'),
                onPressed: editor.canSubmit ? notifier.submit : null,
                child: Text(_submitLabel(localizations, editor)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Запрос видимости после перехода сессии от [previous] к [next].
  ///
  /// Новая ошибка поля получает новый запрос; запрос действует, пока отказ и
  /// черновик остаются прежними. Общий отказ закреплён и запроса не требует.
  IntentionCreationSheetReveal? _failureRevealAfter(
    IntentionEditorState? previous,
    IntentionEditorState next,
  ) {
    final operation = next.operation;
    if (operation is! OperationFailed<Intention>) {
      return null;
    }
    if (previous != null && identical(previous.operation, operation)) {
      return identical(previous.draft, next.draft) ? _failureReveal : null;
    }
    return switch (_failurePlace(operation.failure)) {
      _FailurePlace.title => IntentionCreationSheetReveal(_titleField),
      _FailurePlace.description => IntentionCreationSheetReveal(
        _descriptionField,
      ),
      _FailurePlace.pinned => null,
    };
  }

  /// Передаёт запрос ухода сессии и выполняет её решение.
  Future<void> _requestClose() async {
    switch (ref.read(_provider.notifier).requestClose()) {
      case IntentionCreationClosedImmediately() ||
          IntentionCreationCloseSessionEnded():
        _closeRoute();
      case IntentionCreationCloseNeedsConfirmation(:final confirmation):
        final choice = await showDialog<IntentionCreationCloseChoice>(
          context: context,
          // Подтверждение живёт в стеке маршрута своей формы.
          useRootNavigator: false,
          builder: (_) => _CloseConfirmationDialog(
            provider: _provider,
            confirmation: confirmation,
          ),
        );
        if (!mounted) {
          return;
        }
        // Закрытие диалога без выбора продолжает ввод.
        final resolution = ref
            .read(_provider.notifier)
            .resolveClose(
              confirmation,
              choice ?? IntentionCreationCloseChoice.continueEditing,
            );
        switch (resolution) {
          case IntentionCreationCloseResolution.closed:
            _closeRoute();
          case IntentionCreationCloseResolution.continued ||
              IntentionCreationCloseResolution.outdated:
            break;
        }
      case IntentionCreationCloseAwaitingConfirmation():
        // Ответа уже ожидает единственный диалог этой сессии.
        break;
    }
  }

  /// Объясняет оба критерия действия и включает начальную готовность
  /// черновика только по явному подтверждению.
  ///
  /// Отказ, нажатие вне объяснения и «назад» оставляют готовность
  /// выключенной. Подтверждение принимает только эта сессия и только пока её
  /// черновик редактируется: запоздалый ответ не меняет отправленный или
  /// закрытый черновик.
  Future<void> _confirmReadiness() async {
    if (_isConfirmingReadiness) {
      return;
    }
    _isConfirmingReadiness = true;
    final confirmed = await showDialog<bool>(
      context: context,
      // Объяснение живёт в стеке маршрута своей формы и закрывается с ним.
      useRootNavigator: false,
      builder: (_) => _ReadinessConfirmationDialog(provider: _provider),
    ).whenComplete(() => _isConfirmingReadiness = false);
    if (!mounted || !(confirmed ?? false)) {
      return;
    }
    ref.read(_provider.notifier).confirmReadiness();
  }

  /// Открывает общий выбор тегов для набора черновика этой сессии.
  ///
  /// Выбор добавляет теги только через контракт набора сессии, который после
  /// отправки или закрытия отвергает изменения; возврат из выбора сам
  /// черновик не меняет. Повторное нажатие до закрытия выбора второй выбор не
  /// открывает.
  Future<void> _chooseTags() async {
    if (_isChoosingTags) {
      return;
    }
    switch (ref.read(_provider).draftAvailability) {
      case IntentionDraftAvailability.editable:
        break;
      case IntentionDraftAvailability.submitting ||
          IntentionDraftAvailability.closed:
        return;
    }
    _isChoosingTags = true;
    final tagSet = ref.read(_provider.notifier).draftTagSet;
    try {
      await context.router.push<void>(
        TagCatalogRoute(selectionContext: TagDraftContext(tagSet)),
      );
    } finally {
      _isChoosingTags = false;
    }
  }

  /// Закрывает только маршрут этой формы, минуя повторное обращение к уже
  /// завершённой сессии.
  void _closeRoute() {
    if (_isRouteClosing || !mounted) {
      return;
    }
    _isRouteClosing = true;
    context.router.removeRoute(context.routeData);
  }

  String _submitLabel(
    AppLocalizations localizations,
    IntentionEditorState editor,
  ) => switch (editor.operation) {
    OperationRunning<Intention>() => localizations.editorSaving,
    OperationFailed<Intention>(failure: IntentionUnavailableFailure()) =>
      localizations.commonRetry,
    OperationIdle<Intention>() ||
    OperationSucceeded<Intention>() ||
    OperationFailed<Intention>() => localizations.editorSaveAction,
  };
}

/// Где панель показывает отказ сохранения: под своим полем в прокручиваемых
/// полях или в закреплённой области рядом с сохранением.
enum _FailurePlace { title, description, pinned }

_FailurePlace _failurePlace(IntentionFailure failure) => switch (failure) {
  IntentionTextInputValidationFailure(:final textFailure) =>
    switch (textFailure.field) {
      IntentionTextField.title => _FailurePlace.title,
      IntentionTextField.description => _FailurePlace.description,
      IntentionTextField.titleFilter => _FailurePlace.pinned,
    },
  IntentionGenericValidationFailure() ||
  IntentionCreationTagsMissingFailure() ||
  IntentionNotFoundFailure() ||
  IntentionConflictFailure() ||
  IntentionHasBlockingRelationsFailure() ||
  IntentionUnavailableFailure() ||
  IntentionCorruptionFailure() ||
  IntentionUnexpectedFailure() => _FailurePlace.pinned,
};

String _failureMessage(
  AppLocalizations localizations,
  IntentionFailure failure,
) => switch (failure) {
  IntentionTextInputValidationFailure(:final textFailure) => switch ((
    textFailure.field,
    textFailure.reason,
  )) {
    (IntentionTextField.title, IntentionTextValidationReason.empty) =>
      localizations.editorTitleEmpty,
    (IntentionTextField.title, IntentionTextValidationReason.tooLong) =>
      localizations.editorTitleTooLong,
    (
      IntentionTextField.title,
      IntentionTextValidationReason.invalidUnicodeRepertoire,
    ) =>
      localizations.editorTitleInvalidUnicode,
    (IntentionTextField.description, IntentionTextValidationReason.tooLong) =>
      localizations.editorDescriptionTooLong,
    (
      IntentionTextField.description,
      IntentionTextValidationReason.invalidUnicodeRepertoire,
    ) =>
      localizations.editorDescriptionInvalidUnicode,
    (IntentionTextField.description, IntentionTextValidationReason.empty) ||
    (IntentionTextField.titleFilter, _) => localizations.editorInvalidInput,
  },
  // Объяснение описывает проверку при сохранении; исправление снимает
  // оставшиеся в черновике отсутствующие теги.
  IntentionCreationTagsMissingFailure(:final missingTagIds) =>
    localizations.editorCreateTagsMissing(missingTagIds.length),
  IntentionGenericValidationFailure() => localizations.editorInvalidInput,
  IntentionConflictFailure() => localizations.editorCreateConflict,
  IntentionHasBlockingRelationsFailure() =>
    localizations.editorCreateUnexpected,
  IntentionUnavailableFailure() => localizations.editorCreateUnavailable,
  IntentionCorruptionFailure() => localizations.editorCreateCorruption,
  IntentionNotFoundFailure() ||
  IntentionUnexpectedFailure() => localizations.editorCreateUnexpected,
};

/// Подтверждение закрытия изменённого черновика одной сессии.
///
/// Ответ действует, пока [confirmation] остаётся ожидающим подтверждением
/// сессии. Смена состояния отправки или завершение сессии отключают ответы и
/// закрывают диалог без выбора, поэтому устаревший ответ не меняет форму.
final class _CloseConfirmationDialog extends ConsumerStatefulWidget {
  const _CloseConfirmationDialog({
    required this.provider,
    required this.confirmation,
  });

  final IntentionEditorViewModelProvider provider;
  final IntentionCreationCloseConfirmation confirmation;

  @override
  ConsumerState<_CloseConfirmationDialog> createState() =>
      _CloseConfirmationDialogState();
}

final class _CloseConfirmationDialogState
    extends ConsumerState<_CloseConfirmationDialog> {
  var _isDismissing = false;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final isPending = ref.watch(
      widget.provider.select(
        (editor) => switch (editor.closing) {
          IntentionCreationCloseConfirming(:final confirmation) => identical(
            confirmation,
            widget.confirmation,
          ),
          IntentionCreationCloseNotRequested() ||
          IntentionCreationClosedOnRequest() => false,
        },
      ),
    );
    if (!isPending) {
      _dismissOutdated();
    }
    final (
      title,
      message,
      continueLabel,
      discardLabel,
    ) = switch (widget.confirmation.savingOnClose) {
      IntentionCreationSavingOnClose.notStarted => (
        localizations.editorCloseDiscardTitle,
        localizations.editorCloseDiscardMessage,
        localizations.editorCloseContinueAction,
        localizations.editorCloseDiscardAction,
      ),
      IntentionCreationSavingOnClose.continues => (
        localizations.editorCloseSavingTitle,
        localizations.editorCloseSavingMessage,
        localizations.editorCloseSavingStayAction,
        localizations.editorCloseSavingLeaveAction,
      ),
    };
    final colors = Theme.of(context).colorScheme;
    return AlertDialog(
      key: const ValueKey('intention-editor-close-confirmation'),
      scrollable: true,
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          key: const ValueKey('intention-editor-close-continue'),
          onPressed: isPending
              ? () => _answer(IntentionCreationCloseChoice.continueEditing)
              : null,
          child: Text(continueLabel),
        ),
        FilledButton(
          key: const ValueKey('intention-editor-close-discard'),
          onPressed: isPending
              ? () => _answer(IntentionCreationCloseChoice.discardDraft)
              : null,
          style: FilledButton.styleFrom(
            backgroundColor: colors.error,
            foregroundColor: colors.onError,
          ),
          child: Text(discardLabel),
        ),
      ],
    );
  }

  /// Закрывает диалог с ответом [choice], только пока он остаётся верхним
  /// маршрутом: ответ не может закрыть форму или другой маршрут под ним.
  void _answer(IntentionCreationCloseChoice? choice) {
    if (ModalRoute.of(context)?.isCurrent ?? false) {
      Navigator.of(context).pop(choice);
    }
  }

  void _dismissOutdated() {
    if (_isDismissing) {
      return;
    }
    _isDismissing = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _answer(null);
      }
    });
  }
}

/// Быстрые действия черновика: общий выбор тегов и отметки избранного и
/// начальной готовности.
///
/// Действия меняют только черновик сессии и не отправляют команд графа.
/// Включённое состояние отметок отличается формой значка и признаком
/// включения для экранного диктора, а подсказка называет назначение и
/// состояние, не выдавая черновик за сохранённое намерение.
final class _DraftOptions extends StatelessWidget {
  const _DraftOptions({
    required this.favoriteMark,
    required this.readiness,
    required this.enabled,
    required this.onChooseTags,
    required this.onMarkFavorite,
    required this.onUnmarkFavorite,
    required this.onEnableReadiness,
    required this.onDisableReadiness,
  });

  final FavoriteMark favoriteMark;
  final IntentionReadiness readiness;

  /// Черновик принимает правки: во время отправки и после завершения сессии
  /// действия недоступны.
  final bool enabled;
  final VoidCallback onChooseTags;
  final VoidCallback onMarkFavorite;
  final VoidCallback onUnmarkFavorite;

  /// Начинает включение готовности с объяснения критериев действия.
  final VoidCallback onEnableReadiness;
  final VoidCallback onDisableReadiness;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    // Нажатия отметок не считаются нажатием вне поля ввода: ввод
    // продолжается с прежним фокусом.
    return TextFieldTapRegion(
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          IconButton(
            key: const ValueKey('intention-editor-choose-tags'),
            tooltip: localizations.editorChooseTags,
            onPressed: enabled ? onChooseTags : null,
            icon: const Icon(Icons.label_outline),
          ),
          switch (favoriteMark) {
            FavoriteMark.favorite => _DraftOptionButton(
              optionKey: const ValueKey('intention-editor-favorite'),
              label: localizations.editorFavoriteOption,
              tooltip: localizations.editorFavoriteOptionOn,
              isOn: true,
              icon: Icons.star,
              onPressed: enabled ? onUnmarkFavorite : null,
            ),
            FavoriteMark.notFavorite => _DraftOptionButton(
              optionKey: const ValueKey('intention-editor-favorite'),
              label: localizations.editorFavoriteOption,
              tooltip: localizations.editorFavoriteOptionOff,
              isOn: false,
              icon: Icons.star_border,
              onPressed: enabled ? onMarkFavorite : null,
            ),
          },
          switch (readiness) {
            IntentionReadiness.ready => _DraftOptionButton(
              optionKey: const ValueKey('intention-editor-readiness'),
              label: localizations.editorReadinessOption,
              tooltip: localizations.editorReadinessOptionOn,
              isOn: true,
              icon: Icons.check_circle,
              onPressed: enabled ? onDisableReadiness : null,
            ),
            IntentionReadiness.notReady => _DraftOptionButton(
              optionKey: const ValueKey('intention-editor-readiness'),
              label: localizations.editorReadinessOption,
              tooltip: localizations.editorReadinessOptionOff,
              isOn: false,
              icon: Icons.check_circle_outline,
              onPressed: enabled ? onEnableReadiness : null,
            ),
          },
        ],
      ),
    );
  }
}

/// Переключатель одной быстрой отметки черновика.
///
/// Экранный диктор получает назначение [label] и признак включения [isOn];
/// подсказка [tooltip] показывает их же текстом и потому не повторяется в
/// семантике.
final class _DraftOptionButton extends StatelessWidget {
  const _DraftOptionButton({
    required this.optionKey,
    required this.label,
    required this.tooltip,
    required this.isOn,
    required this.icon,
    required this.onPressed,
  });

  final Key optionKey;
  final String label;
  final String tooltip;
  final bool isOn;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    excludeFromSemantics: true,
    child: MergeSemantics(
      child: Semantics(
        label: label,
        toggled: isOn,
        child: IconButton(
          key: optionKey,
          onPressed: onPressed,
          color: isOn ? Theme.of(context).colorScheme.primary : null,
          icon: Icon(icon),
        ),
      ),
    ),
  );
}

/// Объяснение обоих критериев действия перед включением начальной
/// готовности черновика.
///
/// Подтверждение действует, пока черновик сессии редактируется и остаётся
/// неготовым. Иначе оно становится недоступным, а объяснение закрывается без
/// ответа, поэтому запоздалое нажатие не меняет черновик.
final class _ReadinessConfirmationDialog extends ConsumerStatefulWidget {
  const _ReadinessConfirmationDialog({required this.provider});

  final IntentionEditorViewModelProvider provider;

  @override
  ConsumerState<_ReadinessConfirmationDialog> createState() =>
      _ReadinessConfirmationDialogState();
}

final class _ReadinessConfirmationDialogState
    extends ConsumerState<_ReadinessConfirmationDialog> {
  var _isDismissing = false;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final isPending = ref.watch(
      widget.provider.select(
        (editor) =>
            editor.draft.readiness == IntentionReadiness.notReady &&
            switch (editor.draftAvailability) {
              IntentionDraftAvailability.editable => true,
              IntentionDraftAvailability.submitting ||
              IntentionDraftAvailability.closed => false,
            },
      ),
    );
    if (!isPending) {
      _dismissOutdated();
    }
    return AlertDialog(
      key: const ValueKey('intention-editor-readiness-confirmation'),
      scrollable: true,
      title: Text(localizations.editorReadinessConfirmationTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(localizations.editorReadinessOneDayCriterion),
          const SizedBox(height: 12),
          Text(localizations.editorReadinessClarityCriterion),
        ],
      ),
      actions: [
        TextButton(
          key: const ValueKey('intention-editor-readiness-cancel'),
          onPressed: () => _answer(false),
          child: Text(localizations.editorReadinessCancelAction),
        ),
        FilledButton(
          key: const ValueKey('intention-editor-readiness-confirm'),
          onPressed: isPending ? () => _answer(true) : null,
          child: Text(localizations.editorReadinessConfirmAction),
        ),
      ],
    );
  }

  /// Закрывает объяснение с ответом [confirmed], только пока оно остаётся
  /// верхним маршрутом: ответ не может закрыть форму или другой маршрут.
  void _answer(bool? confirmed) {
    if (ModalRoute.of(context)?.isCurrent ?? false) {
      Navigator.of(context).pop(confirmed);
    }
  }

  void _dismissOutdated() {
    if (_isDismissing) {
      return;
    }
    _isDismissing = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _answer(null);
      }
    });
  }
}
