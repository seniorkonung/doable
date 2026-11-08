/// Собственный приоритет действия: P1 — высший, P4 — низший.
enum ActionPriority {
  p1(1),
  p2(2),
  p3(3),
  p4(4);

  const ActionPriority(this.level);

  final int level;
}
