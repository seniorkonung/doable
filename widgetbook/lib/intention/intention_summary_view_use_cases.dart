import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/presentation/intention_summary_view.dart';
import 'package:doable/src/tag/domain/tag.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:flutter/material.dart';
import 'package:widgetbook/widgetbook.dart';

const _title = 'быть здоровым';
const _longTitle =
    'научиться хорошо плавать и перестать бояться глубины в открытой воде';

/// Состояния строки намерения — [IntentionSummaryView] приложения.
List<WidgetbookUseCase> intentionSummaryViewUseCases() => [
  WidgetbookUseCase(
    name: 'Строка каталога',
    builder: (context) => _catalogRow(context, title: _title),
  ),
  WidgetbookUseCase(
    name: 'Длинное название',
    builder: (context) => _catalogRow(context, title: _longTitle),
  ),
  WidgetbookUseCase(
    name: 'Без тегов',
    builder: (context) =>
        _catalogRow(context, title: _title, tagNames: const []),
  ),
  WidgetbookUseCase(
    name: 'В архиве',
    builder: (context) => _catalogRow(
      context,
      title: _title,
      archiveState: IntentionArchiveState.archived,
    ),
  ),
  WidgetbookUseCase(
    name: 'Количество связей загружается',
    builder: (context) => _catalogRow(
      context,
      title: _title,
      activeRelationCount: const LoadingActiveRelationCount(),
    ),
  ),
  WidgetbookUseCase(
    name: 'Количество связей устарело',
    builder: (context) => _catalogRow(
      context,
      title: _title,
      activeRelationCount: OutdatedActiveRelationCount(4),
    ),
  ),
  WidgetbookUseCase(
    name: 'Количество связей неизвестно',
    builder: (context) => _catalogRow(
      context,
      title: _title,
      activeRelationCount: const UnknownActiveRelationCount(),
    ),
  ),
  WidgetbookUseCase(
    name: 'Участник связи',
    // Страницы связи показывают только название, архивное состояние и
    // количество активных связей.
    builder: (context) => IntentionSummaryView(
      title: _title,
      archiveState: IntentionArchiveState.active,
      activeRelationCount: ConfirmedActiveRelationCount(4),
      showArchiveState: true,
      onTap: () {},
    ),
  ),
];

/// Строка в том виде, в каком её собирает каталог намерений: с готовностью,
/// наличием описания и тегами.
Widget _catalogRow(
  BuildContext context, {
  required String title,
  List<String> tagNames = const ['здоровье', 'каждый день'],
  IntentionArchiveState archiveState = IntentionArchiveState.active,
  ActiveRelationCountView? activeRelationCount,
}) {
  final localizations = AppLocalizations.of(context);
  return IntentionSummaryView(
    title: title,
    archiveState: archiveState,
    // Каталог показывает архивное состояние только в охвате «Все».
    showArchiveState: archiveState == IntentionArchiveState.archived,
    activeRelationCount: activeRelationCount ?? ConfirmedActiveRelationCount(4),
    traits: [
      localizations.catalogNotReady,
      localizations.catalogHasDescription,
    ],
    confirmedTags: [
      for (final (index, name) in tagNames.indexed) _tag(index, name),
    ],
    onTap: () {},
  );
}

Tag _tag(int index, String name) {
  final serialized =
      '00000000-0000-4000-8000-${(index + 1).toString().padLeft(12, '0')}';
  return switch (TagId.decode(serialized)) {
    TagIdDecodingSuccess(:final id) => Tag(
      id: id,
      name: TagName.fromInput(name),
    ),
    InvalidTagIdDecoding() => throw StateError(
      'Идентификатор образца тега недействителен: $serialized',
    ),
  };
}
