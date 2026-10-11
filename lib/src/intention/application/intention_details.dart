import '../../long_term_relation/application/relation_counts.dart';
import '../domain/intention.dart';

final class IntentionDetails {
  const IntentionDetails({
    required this.intention,
    required this.relationCounts,
  });

  final Intention intention;
  final RelationCounts relationCounts;

  int get activeRelationCount => relationCounts.active;
}
