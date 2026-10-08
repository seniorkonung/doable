part of 'tag_navigation_page_test.dart';

void _registerPrimaryNavigationScenarios() {
  testWidgets('основная панель доступна во всех состояниях чтения тега', (
    tester,
  ) async {
    final reads = _Reads();
    addTearDown(reads.dispose);
    await _pumpPage(tester, reads);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(TagNavigationPage)),
      listen: false,
    );
    final provider = tagNavigationViewModelProvider(_tag.id);
    final model = container.read(provider.notifier);
    void expectPanel() {
      expect(find.byType(AppNavigationBar), findsOneWidget);
      expect(appNavigationDestinations().hitTestable(), findsNWidgets(3));
      for (final destination in AppDestination.values) {
        final entry = appNavigationDestination(destination);
        expect(entry.hitTestable(), findsOneWidget);
        expect(
          tester.getSemantics(entry),
          containsSemantics(
            hasSelectedState: true,
            isSelected: destination == AppDestination.home,
            hasTapAction: true,
          ),
          reason: 'Пункт ${destination.name}',
        );
      }
      expect(tester.takeException(), isNull);
    }

    expect(container.read(provider), isA<TagNavigationInitialLoading>());
    expectPanel();
    reads.fail(0, const TaggedIntentionsUnavailableFailure());
    await tester.pumpAndSettle();
    expect(container.read(provider), isA<TagNavigationInitialFailure>());
    expectPanel();
    unawaited(model.retryFirstPage());
    await tester.pump();
    reads.page(1, []);
    await tester.pumpAndSettle();
    expect((container.read(provider) as TagNavigationLoaded).isEmpty, isTrue);
    expectPanel();

    model.setScope(TaggedIntentionsScope.archived);
    await tester.pump();
    reads.page(2, [_intention(2, archived: true)], cursor: _Cursor());
    await tester.pumpAndSettle();
    expectPanel();
    unawaited(model.loadMore());
    await tester.pump();
    expect(
      (container.read(provider) as TagNavigationLoaded).pageStatus,
      isA<TagNavigationPageLoading>(),
    );
    expectPanel();
    reads.fail(3, const TaggedIntentionsUnavailableFailure());
    await tester.pumpAndSettle();
    expectPanel();

    reads.watch.add(
      TagReadSuccess(GraphSnapshot(value: _tag, revision: const _Revision(2))),
    );
    await tester.pump();
    expect(
      (container.read(provider) as TagNavigationLoaded).freshness,
      TagNavigationFreshness.refreshing,
    );
    expectPanel();
    reads.fail(4, const TaggedIntentionsUnavailableFailure());
    await tester.pumpAndSettle();
    expectPanel();
    reads.watch.add(
      const TagReadSuccess(GraphSnapshot(value: null, revision: _Revision(3))),
    );
    await tester.pumpAndSettle();
    expect(container.read(provider), isA<TagNavigationTagMissing>());
    expectPanel();
  });
}
