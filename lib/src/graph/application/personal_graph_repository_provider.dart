import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'personal_graph_repository.dart';

part 'personal_graph_repository_provider.g.dart';

@Riverpod(keepAlive: true)
PersonalGraphRepository personalGraphRepository(Ref ref) {
  throw StateError(
    'PersonalGraphRepository должен быть предоставлен владеющим AppRuntime.',
  );
}
