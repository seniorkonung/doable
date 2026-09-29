import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';

import '../../../app/routing/app_router.gr.dart';
import '../../application/tag_catalog.dart';
import '../../domain/tag.dart';
import '../../../intention/domain/intention_id.dart';
import 'tag_catalog_view.dart';

@RoutePage()
final class TagCatalogPage extends StatelessWidget {
  const TagCatalogPage({this.intentionId, super.key});

  final IntentionId? intentionId;

  @override
  Widget build(BuildContext context) => TagCatalogView(
    mode: switch (intentionId) {
      null => const TagCatalogBrowseMode(),
      final intentionId => TagCatalogSelectionMode(intentionId),
    },
    onOpenEditor: (editorContext) =>
        context.router.push<Tag>(TagEditorRoute(editorContext: editorContext)),
    onOpenNavigation: (tagId) =>
        unawaited(context.router.push<void>(TagNavigationRoute(tagId: tagId))),
  );
}
