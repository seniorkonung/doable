import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';

import '../../../app/routing/app_router.gr.dart';
import '../../application/tag_catalog.dart';
import '../../domain/tag.dart';
import '../../domain/tag_target.dart';
import 'tag_catalog_view.dart';

@RoutePage()
final class TagCatalogPage extends StatelessWidget {
  const TagCatalogPage({this.target, super.key});

  final TagTarget? target;

  @override
  Widget build(BuildContext context) => TagCatalogView(
    mode: switch (target) {
      null => const TagCatalogBrowseMode(),
      IntentionTagTarget(:final intentionId) => TagCatalogSelectionMode(
        intentionId,
      ),
      LongTermRelationTagTarget() => throw ArgumentError(
        'Тег можно назначить только намерению.',
      ),
    },
    onOpenEditor: (editorContext) =>
        context.router.push<Tag>(TagEditorRoute(editorContext: editorContext)),
    onOpenNavigation: (tagId) =>
        unawaited(context.router.push<void>(TagNavigationRoute(tagId: tagId))),
  );
}
