import 'package:flutter/material.dart';

import 'game_screen.dart';
import 'game_state.dart';

void main() {
  runApp(const ComplexityLadderApp());
}

class ComplexityLadderApp extends StatefulWidget {
  const ComplexityLadderApp({super.key});

  @override
  State<ComplexityLadderApp> createState() => _ComplexityLadderAppState();
}

class _ComplexityLadderAppState extends State<ComplexityLadderApp> {
  final GameState game = GameState();

  @override
  void initState() {
    super.initState();
    game.rebuild();
  }

  @override
  void dispose() {
    game.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: game,
      builder: (BuildContext context, Widget? child) {
        ThemeData light = ThemeData(
          colorSchemeSeed: game.youColor(false),
          brightness: Brightness.light,
          useMaterial3: true,
        );
        ThemeData dark = ThemeData(
          colorSchemeSeed: game.youColor(true),
          brightness: Brightness.dark,
          useMaterial3: true,
        );
        return MaterialApp(
          title: 'Complexity Ladder',
          debugShowCheckedModeBanner: false,
          theme: light,
          darkTheme: dark,
          themeMode: ThemeMode.system,
          home: GameScreen(game: game),
        );
      },
    );
  }
}
