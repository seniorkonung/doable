/// Собственный приоритет дневного выбора: P1 — высший, P4 — низший.
enum DailyChoicePriority {
  p1(1),
  p2(2),
  p3(3),
  p4(4);

  const DailyChoicePriority(this.level);

  final int level;
}
