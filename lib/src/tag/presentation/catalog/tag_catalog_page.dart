import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';

import '../../../app/routing/app_router.gr.dart';
import '../../domain/tag.dart';
import 'tag_catalog_view.dart';
import 'tag_selection_context.dart';

/// Единственная страница каталога и общего выбора тегов.
///
/// Контекст выбора задаёт вызывающий сценарий: просмотр каталога, постоянное
/// назначение существующему намерению или добавление в набор черновика
/// сессии создания. Страница передаёт его общему компоненту вместе с
/// маршрутами редактора и навигации по тегу. Сессию черновика страница не
/// удерживает и не завершает: её владелец остаётся под выбором, а закрытие
/// страницы закрывает только выбор.
@RoutePage()
final class TagCatalogPage extends StatelessWidget {
  const TagCatalogPage({
    this.selectionContext = const TagBrowseContext(),
    super.key,
  });

  final TagSelectionContext selectionContext;

  @override
  Widget build(BuildContext context) => TagCatalogView(
    selectionContext: selectionContext,
    onOpenEditor: (editorContext) =>
        context.router.push<Tag>(TagEditorRoute(editorContext: editorContext)),
    onOpenNavigation: (tagId) =>
        unawaited(context.router.push<void>(TagNavigationRoute(tagId: tagId))),
  );
}
