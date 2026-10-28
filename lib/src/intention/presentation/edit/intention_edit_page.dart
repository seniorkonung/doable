import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart' hide TextField;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../design_system/components/confirm_dialog.dart';
import '../../../design_system/components/notice.dart';
import '../../../design_system/components/text_field.dart';
import '../../../design_system/components/top_bar.dart';
import '../../../design_system/doable_metrics.dart';
import '../../../graph/presentation/operation_failure_presentation.dart';
import '../../domain/intention.dart';
import '../../domain/intention_id.dart';
import '../../domain/intention_text.dart';
import '../operation/operation_state.dart';
import 'intention_edit_failure_message.dart';
import 'intention_edit_state.dart';
import 'intention_edit_view_model.dart';

/// Страница-задача «Изменить намерение» с названием и описанием.
///
/// Страница открывается над полученными подробными данными намерения и
/// держит ключ своей сессии: повторное открытие начинает новую сессию со
/// снимком сохранённых текстов. Успешное сохранение закрывает страницу без
/// сообщения, а отказ остаётся на ней вместе с введённым текстом.
///
/// Стрелка и системное «назад» не закрывают маршрут сами: уход решает
/// сессия, а изменённый текст отменяется только ответом на вопрос.
@RoutePage()
final class IntentionEditPage extends ConsumerStatefulWidget {
  const IntentionEditPage({required this.intentionId, super.key});

  final IntentionId intentionId;

  @override
  ConsumerState<IntentionEditPage> createState() => _IntentionEditPageState();
}

final class _IntentionEditPageState extends ConsumerState<IntentionEditPage> {
  static const _descriptionMinLines = 5;
  static const _descriptionMaxLines = 13;

  final _formKey = IntentionEditFormKey();

  /// Место текущего отказа: над полями или под полем, к которому он
  /// относится. Отказ показывается только в одном месте.
  final _failureKey = GlobalKey();
  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;

  IntentionEditViewModelProvider get _provider =>
      intentionEditViewModelProvider(_formKey, widget.intentionId);

  @override
  void initState() {
    super.initState();
    final opened = ref.read(_provider);
    // Курсор стоит в конце названия.
    _titleController = TextEditingController.fromValue(
      TextEditingValue(
        text: opened.title,
        selection: TextSelection.collapsed(offset: opened.title.length),
      ),
    );
    _descriptionController = TextEditingController(text: opened.description);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final edit = ref.watch(_provider);
    final model = ref.read(_provider.notifier);
    ref.listen(_provider, (previous, next) {
      if (previous?.operation is! OperationSucceeded<Intention> &&
          next.operation is OperationSucceeded<Intention>) {
        _closeRoute();
      }
      if (next.operation is OperationFailed<Intention> &&
          !identical(previous?.operation, next.operation)) {
        _revealFailure();
      }
    });

    final operation = edit.operation;
    final titleFailure = intentionEditFieldFailureMessage(
      localizations,
      operation,
      IntentionTextField.title,
    );
    final descriptionFailure = intentionEditFieldFailureMessage(
      localizations,
      operation,
      IntentionTextField.description,
    );
    final generalFailure = intentionEditGeneralFailureMessage(
      localizations,
      operation,
    );
    final isDraftFixed = !edit.acceptsDraftChanges;
    return PopScope<Object?>(
      // Маршрут не закрывается сам: решение принимает сессия.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          unawaited(_requestClose());
        }
      },
      child: Scaffold(
        appBar: TopBar.withButton(
          context,
          title: localizations.intentionEditTitle,
          backLabel: MaterialLocalizations.of(context).backButtonTooltip,
          onBack: () => unawaited(_requestClose()),
          buttonLabel: localizations.intentionEditSaveAction,
          onButtonPressed: edit.canSave ? model.save : null,
        ),
        body: SafeArea(
          top: false,
          // Поля не перестраиваются при прокрутке: автофокус названия
          // срабатывает только при открытии.
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              DoableMetrics.space5,
              DoableMetrics.space2,
              DoableMetrics.space5,
              DoableMetrics.space5,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (generalFailure != null) ...[
                  Notice.content(
                    key: _failureKey,
                    message: OperationFailurePresentation(
                      claim: edit.failurePresentation,
                      message: generalFailure,
                      messageKey: const ValueKey('intention-edit-failure'),
                      inheritsColor: true,
                    ),
                  ),
                  const SizedBox(height: DoableMetrics.space3),
                ],
                TextField.multiline(
                  key: const ValueKey('intention-edit-title'),
                  controller: _titleController,
                  placeholder: localizations.intentionEditNameLabel,
                  label: localizations.intentionEditNameLabel,
                  kind: TextFieldKind.name,
                  autofocus: true,
                  readOnly: isDraftFixed,
                  onChanged: model.changeTitle,
                  error: titleFailure == null
                      ? null
                      : OperationFailurePresentation(
                          key: _failureKey,
                          claim: edit.failurePresentation,
                          message: titleFailure,
                          inheritsColor: true,
                        ),
                ),
                const SizedBox(height: DoableMetrics.space2),
                TextField.multiline(
                  key: const ValueKey('intention-edit-description'),
                  controller: _descriptionController,
                  placeholder:
                      localizations.intentionEditDescriptionPlaceholder,
                  label: localizations.intentionEditDescriptionLabel,
                  minLines: _descriptionMinLines,
                  maxLines: _descriptionMaxLines,
                  readOnly: isDraftFixed,
                  onChanged: model.changeDescription,
                  error: descriptionFailure == null
                      ? null
                      : OperationFailurePresentation(
                          key: _failureKey,
                          claim: edit.failurePresentation,
                          message: descriptionFailure,
                          inheritsColor: true,
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Прокручивает содержимое к месту нового отказа после его кадра:
  /// «Сохранить» нажимается из любой позиции прокрутки, а места отказов
  /// стоят в начале содержимого. Пока сообщение вне видимой части, кадр не
  /// подтверждает его предъявление.
  void _revealFailure() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final failure = _failureKey.currentContext;
      if (!mounted || failure == null) return;
      unawaited(
        Scrollable.ensureVisible(
          failure,
          alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtStart,
        ),
      );
    });
  }

  /// Закрывает экран по решению сессии; изменённый текст закрывается только
  /// после ответа «Отменить».
  Future<void> _requestClose() async {
    switch (ref.read(_provider.notifier).requestClose()) {
      case IntentionEditCloseDecision.close:
        _closeRoute();
      case IntentionEditCloseDecision.askDiscard:
        final localizations = AppLocalizations.of(context);
        final discarded = await showDiscardDialog(
          context: context,
          title: localizations.intentionEditDiscardTitle,
          text: localizations.intentionEditDiscardMessage,
          discardLabel: localizations.intentionEditDiscardAction,
          keepLabel: localizations.intentionEditContinueAction,
        );
        if (discarded) {
          _closeRoute();
        }
    }
  }

  /// Закрывает только маршрут этой страницы, если он ещё в истории.
  /// Наличие маршрута проверяется по matchId, как у removeRoute:
  /// https://pub.dev/documentation/auto_route/11.1.0/auto_route/StackRouter/removeRoute.html
  void _closeRoute() {
    if (!mounted) return;
    final route = context.routeData;
    if (context.router.stackData.any(
      (entry) => entry.matchId == route.matchId,
    )) {
      context.router.removeRoute(route);
    }
  }
}
