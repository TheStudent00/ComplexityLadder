import 'package:flutter/material.dart';
import 'package:ladder_core/ladder_core.dart';

import 'game_state.dart';

/// All eight physics switches of the Complexity Ladder, shown in the drawer.
/// Flipping `thr`, `directed`, `once`, `alt`, or `cross` re-evaluates the
/// active board in place; flipping `open`, `two`, or `coded` synthesizes a
/// board for the new regime.
class SwitchBoard extends StatelessWidget {
  final GameState game;

  const SwitchBoard({super.key, required this.game});

  @override
  Widget build(BuildContext context) {
    Switches s = game.switches;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _switchRow(
          context,
          label: 'threshold',
          leftText: '0',
          rightText: '2',
          isRight: s.thr == 2,
          onSelectRight: (bool r) => game.setSwitches(s.copyWith(thr: r ? 2 : 0)),
        ),
        _switchRow(
          context,
          label: 'centres',
          leftText: 'open (walk)',
          rightText: 'closed',
          isRight: !s.open,
          onSelectRight: (bool r) => game.setSwitches(s.copyWith(open: !r)),
        ),
        _switchRow(
          context,
          label: 'connectors',
          leftText: 'both ways',
          rightText: 'one way',
          isRight: s.directed,
          onSelectRight: (bool r) => game.setSwitches(s.copyWith(directed: r)),
        ),
        _switchRow(
          context,
          label: 'players',
          leftText: 'one',
          rightText: 'two',
          isRight: s.two,
          onSelectRight: (bool r) => game.setSwitches(s.copyWith(two: r)),
        ),
        _switchRow(
          context,
          label: 'slides',
          leftText: 'free',
          rightText: 'each once',
          isRight: s.once,
          onSelectRight: (bool r) => game.setSwitches(s.copyWith(once: r)),
          inert: s.open && s.thr == 0,
        ),
        _switchRow(
          context,
          label: '∀ cells',
          leftText: 'off',
          rightText: 'on',
          isRight: s.alt,
          onSelectRight: (bool r) => game.setSwitches(s.copyWith(alt: r)),
          inert: !s.open,
        ),
        _switchRow(
          context,
          label: '2×2 tiles',
          leftText: 'open',
          rightText: 'folded',
          isRight: s.coded,
          onSelectRight: (bool r) => game.setSwitches(s.copyWith(coded: r)),
        ),
        _switchRow(
          context,
          label: 'crossings',
          leftText: 'bridge',
          rightText: 'ordinary cell',
          isRight: !s.cross,
          onSelectRight: (bool r) => game.setSwitches(s.copyWith(cross: !r)),
          inert: !s.open,
        ),
      ],
    );
  }

  Widget _switchRow(
    BuildContext context, {
    required String label,
    required String leftText,
    required String rightText,
    required bool isRight,
    required ValueChanged<bool> onSelectRight,
    bool inert = false,
  }) {
    ColorScheme colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: inert ? colors.onSurfaceVariant.withValues(alpha: 0.65) : colors.onSurface,
              ),
            ),
          ),
          Expanded(
            child: SegmentedButton<bool>(
              showSelectedIcon: false,
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              segments: [
                ButtonSegment<bool>(
                  value: false,
                  label: Text(leftText, style: const TextStyle(fontSize: 13)),
                ),
                ButtonSegment<bool>(
                  value: true,
                  label: Text(rightText, style: const TextStyle(fontSize: 13)),
                ),
              ],
              selected: {isRight},
              onSelectionChanged: (Set<bool> sel) => onSelectRight(sel.first),
            ),
          ),
        ],
      ),
    );
  }
}

/// Vertical wheel over the nine rungs (`2EXPTIME` at top down to `L` at bottom)
/// for narrow/portrait screens.
class RungWheel extends StatefulWidget {
  final GameState game;

  const RungWheel({super.key, required this.game});

  static const double itemExtent = 38;
  static const int visibleItems = 3;

  @override
  State<RungWheel> createState() => _RungWheelState();
}

class _RungWheelState extends State<RungWheel> {
  late FixedExtentScrollController controller;
  bool scrolling = false;

  int indexOf(Switches s) {
    for (int i = 0; i < rungs.length; i++) {
      if (rungs[i].switches == s) return rungs.length - 1 - i;
    }
    return -1;
  }

  RungPreset rungAt(int wheelIdx) => rungs[rungs.length - 1 - wheelIdx];

  @override
  void initState() {
    super.initState();
    int at = indexOf(widget.game.switches);
    controller = FixedExtentScrollController(initialItem: at < 0 ? 4 : at);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void followGame() {
    if (scrolling || !controller.hasClients) return;
    int wanted = indexOf(widget.game.switches);
    if (wanted >= 0 && controller.selectedItem != wanted) {
      controller.jumpToItem(wanted);
    }
  }

  bool onScroll(ScrollNotification note) {
    if (note is ScrollStartNotification) scrolling = true;
    if (note is ScrollEndNotification) {
      scrolling = false;
      RungPreset settled = rungAt(controller.selectedItem);
      if (settled.switches != widget.game.switches) {
        widget.game.setRung(settled);
      }
    }
    return false;
  }

  void stepTo(int wheelIdx) {
    if (scrolling) return;
    widget.game.setRung(rungAt(wheelIdx));
    controller.animateToItem(
      wheelIdx,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => followGame());
    ColorScheme colors = Theme.of(context).colorScheme;
    double height = RungWheel.itemExtent * RungWheel.visibleItems;
    bool custom = widget.game.rung == null;

    List<Widget> items = [];
    for (int i = 0; i < rungs.length; i++) {
      RungPreset r = rungAt(i);
      bool selected = r.switches == widget.game.switches;
      items.add(Center(
        child: Text(
          r.colLabel,
          style: TextStyle(
            fontSize: selected ? 18 : 15,
            fontWeight: selected ? FontWeight.bold : FontWeight.w500,
            color: selected ? colors.primary : colors.onSurfaceVariant,
          ),
        ),
      ));
    }

    int at = indexOf(widget.game.switches);
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: height,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  height: RungWheel.itemExtent,
                  decoration: BoxDecoration(
                    color: colors.primary.withValues(alpha: custom ? 0.05 : 0.14),
                    border: Border.all(color: custom ? colors.outlineVariant : colors.primary, width: 1.8),
                    borderRadius: BorderRadius.circular(9),
                  ),
                ),
                NotificationListener<ScrollNotification>(
                  onNotification: onScroll,
                  child: ListWheelScrollView(
                    controller: controller,
                    itemExtent: RungWheel.itemExtent,
                    physics: const FixedExtentScrollPhysics(),
                    diameterRatio: 2.3,
                    overAndUnderCenterOpacity: 0.62,
                    children: items,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 6),
        SizedBox(
          height: height,
          width: 72,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _sideButton(Icons.arrow_upward, 'harder', at > 0 ? () => stepTo(at - 1) : null),
              ),
              Expanded(
                child: _sideButton(Icons.arrow_downward, 'easier', at >= 0 && at < rungs.length - 1 ? () => stepTo(at + 1) : null),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _sideButton(IconData icon, String text, VoidCallback? onPressed) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 22),
            Text(text, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }
}

/// Full nine-rung class column (`2EXPTIME ·` down to `L`) shown on wide screens.
class RungColumn extends StatelessWidget {
  final GameState game;

  const RungColumn({super.key, required this.game});

  @override
  Widget build(BuildContext context) {
    ColorScheme colors = Theme.of(context).colorScheme;
    List<Widget> cards = [];
    for (int r = rungs.length - 1; r >= 0; r--) {
      RungPreset preset = rungs[r];
      bool active = preset.switches == game.switches;
      cards.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: () => game.setRung(preset),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: active ? colors.primary.withValues(alpha: 0.16) : colors.surface,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: active ? colors.primary : colors.outlineVariant,
                  width: active ? 1.6 : 0.9,
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      preset.colLabel,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: active ? FontWeight.bold : FontWeight.w500,
                        color: active ? colors.primary : colors.onSurface,
                      ),
                    ),
                  ),
                  Text(
                    preset.spaceBound,
                    style: TextStyle(fontSize: 10.5, fontFamily: 'monospace', color: colors.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Complexity Class Ladder', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold, color: colors.onSurface)),
        const SizedBox(height: 4),
        ...cards,
      ],
    );
  }
}

/// Compact or full-width selector between playing Green and playing Purple.
class PlayerColorToggle extends StatelessWidget {
  final GameState game;
  final bool compact;

  const PlayerColorToggle({super.key, required this.game, this.compact = false});

  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    ColorScheme colors = Theme.of(context).colorScheme;
    Color greenDot = isDark ? GameState.kGreenDark : GameState.kGreenLight;
    Color purpleDot = isDark ? GameState.kPurpleDark : GameState.kPurpleLight;

    if (compact) {
      return Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: colors.outlineVariant, width: 1.2),
          color: colors.surfaceContainerLow,
        ),
        padding: const EdgeInsets.all(2.5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _pill(
              selected: !game.playAsPurple,
              dotColor: greenDot,
              label: 'Green',
              onTap: () => game.setPlayAsPurple(false),
              colors: colors,
            ),
            _pill(
              selected: game.playAsPurple,
              dotColor: purpleDot,
              label: 'Purple',
              onTap: () => game.setPlayAsPurple(true),
              colors: colors,
            ),
          ],
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('Color: ', style: TextStyle(fontSize: 14)),
        SegmentedButton<bool>(
          showSelectedIcon: false,
          style: const ButtonStyle(visualDensity: VisualDensity.compact),
          segments: [
            ButtonSegment<bool>(
              value: false,
              label: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.circle, size: 12, color: greenDot),
                  const SizedBox(width: 5),
                  const Text('Green', style: TextStyle(fontSize: 13.5)),
                ],
              ),
            ),
            ButtonSegment<bool>(
              value: true,
              label: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.circle, size: 12, color: purpleDot),
                  const SizedBox(width: 5),
                  const Text('Purple', style: TextStyle(fontSize: 13.5)),
                ],
              ),
            ),
          ],
          selected: {game.playAsPurple},
          onSelectionChanged: (Set<bool> s) => game.setPlayAsPurple(s.first),
        ),
      ],
    );
  }

  Widget _pill({
    required bool selected,
    required Color dotColor,
    required String label,
    required VoidCallback onTap,
    required ColorScheme colors,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(15),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4.5),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(15),
          color: selected ? dotColor.withValues(alpha: 0.20) : Colors.transparent,
          border: selected ? Border.all(color: dotColor, width: 1.4) : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                color: selected ? colors.onSurface : colors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Toggle between coupled perimeter 1-tokens (default) and classic center-walk on `L / NL / P`.
class WalkViewToggle extends StatelessWidget {
  final GameState game;

  const WalkViewToggle({super.key, required this.game});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const SizedBox(
          width: 96,
          child: Text(
            'L/NL/P view',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
        ),
        Expanded(
          child: SegmentedButton<bool>(
            showSelectedIcon: false,
            style: const ButtonStyle(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            segments: const [
              ButtonSegment<bool>(
                value: true,
                label: Text('perimeter (1s)', style: TextStyle(fontSize: 13)),
              ),
              ButtonSegment<bool>(
                value: false,
                label: Text('center walk', style: TextStyle(fontSize: 13)),
              ),
            ],
            selected: {game.walkPerimeterView},
            onSelectionChanged: (Set<bool> s) => game.setWalkPerimeterView(s.first),
          ),
        ),
      ],
    );
  }
}

/// Grid size `n x n` (`4x4`, `5x5`, `6x6`), player color, and reproducible `Seed` controls.
class ParamRow extends StatelessWidget {
  final GameState game;

  const ParamRow({super.key, required this.game});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        PlayerColorToggle(game: game),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Grid: '),
            SegmentedButton<int>(
              showSelectedIcon: false,
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
              segments: const [
                ButtonSegment<int>(value: 4, label: Text('4×4')),
                ButtonSegment<int>(value: 5, label: Text('5×5')),
                ButtonSegment<int>(value: 6, label: Text('6×6')),
              ],
              selected: {game.gridN},
              onSelectionChanged: (Set<int> s) => game.setGridN(s.first),
            ),
          ],
        ),
        SeedField(game: game),
      ],
    );
  }
}

class SeedField extends StatefulWidget {
  final GameState game;

  const SeedField({super.key, required this.game});

  @override
  State<SeedField> createState() => _SeedFieldState();
}

class _SeedFieldState extends State<SeedField> {
  late TextEditingController controller;

  @override
  void initState() {
    super.initState();
    controller = TextEditingController(text: '${widget.game.seed}');
  }

  @override
  void didUpdateWidget(SeedField oldWidget) {
    super.didUpdateWidget(oldWidget);
    String cur = '${widget.game.seed}';
    if (controller.text != cur) controller.text = cur;
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('Seed'),
        const SizedBox(width: 6),
        SizedBox(
          width: 68,
          child: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            decoration: const InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.symmetric(vertical: 6),
            ),
            onSubmitted: (String text) {
              int? val = int.tryParse(text);
              if (val != null) widget.game.setSeed(val);
            },
          ),
        ),
        TextButton.icon(
          onPressed: widget.game.rollNewSeed,
          icon: const Icon(Icons.refresh, size: 18),
          label: const Text('new'),
        ),
      ],
    );
  }
}

/// Undo, redo, reset, 2-tap hint, and `[↻ new]`.
class PlayRow extends StatelessWidget {
  final GameState game;

  const PlayRow({super.key, required this.game});

  @override
  Widget build(BuildContext context) {
    bool idle = !game.replying && game.drag == null;
    bool hintable = game.yourTurn && game.solve?.action != null;
    return Row(
      children: [
        _playButton(Icons.undo, 'undo', idle && game.history.isNotEmpty ? game.undo : null),
        _playButton(Icons.redo, 'redo', idle && game.redoStack.isNotEmpty ? game.redo : null),
        _playButton(Icons.replay, 'reset', idle ? game.reset : null),
        _playButton(
          Icons.lightbulb_outline,
          game.hint == null ? 'hint' : 'make it',
          hintable ? game.hintStep : null,
        ),
        _playButton(Icons.refresh, 'new', idle ? game.rollNewSeed : null),
      ],
    );
  }

  Widget _playButton(IconData icon, String label, VoidCallback? onPressed) {
    return Expanded(
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 2)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 25),
            Text(label, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }
}

class StatusLine extends StatelessWidget {
  final GameState game;

  const StatusLine({super.key, required this.game});

  @override
  Widget build(BuildContext context) {
    ColorScheme colors = Theme.of(context).colorScheme;
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color col = colors.onSurfaceVariant;
    if (game.solved) {
      col = game.youColor(isDark);
    } else if (game.lost || (game.solve != null && game.solve!.dist == null && !game.replying)) {
      col = colors.error;
    }
    return Text(
      game.statusText(),
      textAlign: TextAlign.center,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(color: col, fontSize: 14.5, fontWeight: FontWeight.w500),
    );
  }
}
