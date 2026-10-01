import 'package:flutter/material.dart';

/// Экран-песочница: страница одного намерения.
final class IntentionScreen extends StatelessWidget {
  const IntentionScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Намерение')),
    body: const Center(child: Text('быть здоровым')),
  );
}
