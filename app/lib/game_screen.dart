import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'board_widget.dart';
import 'controls.dart';
import 'game_state.dart';
import 'panels.dart';

/// Responsive screen for Complexity Ladder (manual play on the Grid view):
/// - Portrait phone (`< 840px`): non-scrolling screen with header, interactive
///   grid board canvas, `RungWheel`, and `PlayRow`.
/// - Wide tablet / desktop (`>= 840px`): playable Grid Board alongside the
///   nine-rung Complexity Class Ladder + controls.
class GameScreen extends StatelessWidget {
  final GameState game;

  const GameScreen({super.key, required this.game});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 50,
        titleSpacing: 4,
        title: const FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            'Complexity Ladder',
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.w600),
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ListenableBuilder(
              listenable: game,
              builder: (BuildContext context, Widget? child) => PlayerColorToggle(
                game: game,
                compact: true,
              ),
            ),
          ),
        ],
      ),
      drawerEdgeDragWidth: 0, // Board owns every drag; drawer opens from menu icon.
      drawer: ListenableBuilder(
        listenable: game,
        builder: (BuildContext context, Widget? child) => _settingsDrawer(context),
      ),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: game,
          builder: (BuildContext context, Widget? child) {
            return LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                bool wide = constraints.maxWidth >= 840;
                return wide ? _wideLayout(context) : _narrowLayout(context);
              },
            );
          },
        ),
      ),
    );
  }

  String _headerTitle() {
    if (game.solved) return '✓ SOLVED (★ reached goal cell)';
    if (game.lost) {
      String opp = game.oppColorName;
      String capOpp = '${opp[0].toUpperCase()}${opp.substring(1)}';
      return '✗ $capOpp opponent reached ★ first';
    }
    return game.verdict.className;
  }

  String _ruleSubtitle() {
    if (game.usePerimeterWalk) {
      int? idx = game.rung?.index;
      String crossTxt = game.switches.cross ? ' · crossing bridges' : ' · crossings ordinary';
      if (idx == 0) {
        return 'Threshold E−1 · coupled perimeter 1s · 2-way connectors$crossTxt';
      }
      if (idx == 1) {
        return 'Threshold E−1 · coupled perimeter 1s · 1-way connectors$crossTxt';
      }
      if (idx == 2) {
        return 'Threshold E−1 · coupled perimeter 1s · 1-way · opponent picks exit at ∀';
      }
      return 'Threshold E−1 · coupled perimeter 1s · ${game.switches.directed ? '1-way' : '2-way'}$crossTxt';
    }
    return game.verdict.ruleTitle;
  }

  Widget _boardHeader(BuildContext context) {
    ColorScheme colors = Theme.of(context).colorScheme;
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color titleCol = game.solved
        ? game.youColor(isDark)
        : (game.lost ? colors.error : colors.onSurface);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _headerTitle(),
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: titleCol),
          ),
          Text(
            _ruleSubtitle(),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 13.5, color: colors.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _narrowLayout(BuildContext context) {
    return Column(
      children: [
        _boardHeader(context),
        Expanded(child: BoardWidget(game: game)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
          child: StatusLine(game: game),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 2, 8, 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RungWheel(game: game),
              const SizedBox(height: 2),
              PlayRow(game: game),
            ],
          ),
        ),
      ],
    );
  }

  Widget _wideLayout(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  children: [
                    _boardHeader(context),
                    Expanded(child: BoardWidget(game: game)),
                    StatusLine(game: game),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 264,
            child: Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      RungColumn(game: game),
                      const Divider(height: 14),
                      PlayRow(game: game),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _settingsDrawer(BuildContext context) {
    double width = math.min(MediaQuery.sizeOf(context).width * 0.92, 400);
    return Drawer(
      width: width,
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
          children: [
            const Text('L / NL / P presentation', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 6),
            WalkViewToggle(game: game),
            const Divider(height: 20),
            const Text('Physics switches (8)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 6),
            SwitchBoard(game: game),
            const Divider(height: 20),
            const Text('Grid & seed', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            ParamRow(game: game),
            const Divider(height: 20),
            ProofPanel(game: game),
            const SizedBox(height: 8),
            LadderPanel(game: game),
          ],
        ),
      ),
    );
  }
}
