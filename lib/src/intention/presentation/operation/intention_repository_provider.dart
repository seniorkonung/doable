import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../application/intention_repository.dart';

part 'intention_repository_provider.g.dart';

@Riverpod(keepAlive: true)
IntentionRepository intentionRepository(Ref ref) {
  throw StateError(
    'IntentionRepository должен быть предоставлен владеющим AppRuntime.',
  );
}
