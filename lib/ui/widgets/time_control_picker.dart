import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../game/defaults.dart';
import '../theme/palette.dart';
import 'option_button.dart';

/// The name each time choice is shown under on the setup screens (the
/// design's `TIMES`).
extension TimeChoiceLabel on TimeChoice {
  String get label => switch (this) {
    TimeChoice.untimed => 'Untimed',
    TimeChoice.blitz => 'Blitz 5+0',
    TimeChoice.rapid => 'Rapid 10+5',
    TimeChoice.classical => 'Classical 30+0',
    TimeChoice.custom => 'Custom',
  };
}

/// A press held this long starts repeating the step.
const stepperHoldDelay = Duration(milliseconds: 400);

/// Held, a stepper steps again this often.
const stepperRepeat = Duration(milliseconds: 80);

/// A stepper at its end is drawn at this opacity.
const disabledStepperOpacity = .4;

/// How long choosing Custom takes to scroll its steppers into view.
const stepperRevealDuration = Duration(milliseconds: 200);

/// Called with the chosen time and the custom pair, changed or not.
typedef TimeChanged = void Function(
  TimeChoice time,
  int minutes,
  int increment,
);

/// The setup screens' time control: the five choices in the design's
/// two-column grid and, while Custom is chosen, the minutes and increment
/// steppers. Its keys are `<keyPrefix>-time-<choice>`,
/// `<keyPrefix>-minutes-dec|-inc` and `<keyPrefix>-increment-dec|-inc`.
class TimeControlPicker extends StatefulWidget {
  const TimeControlPicker({
    super.key,
    required this.selected,
    required this.custom,
    required this.onChanged,
    required this.keyPrefix,
    this.accent = Accent.teal,
  });

  final TimeChoice selected;
  final CustomTime custom;
  final TimeChanged onChanged;
  final String keyPrefix;
  final Accent accent;

  @override
  State<TimeControlPicker> createState() => _TimeControlPickerState();
}

class _TimeControlPickerState extends State<TimeControlPicker> {
  final _steppers = GlobalKey();

  /// Set when Custom is chosen by a tap: the next frame brings the
  /// steppers into view.
  bool _reveal = false;

  void _choose(TimeChoice time) {
    if (time == TimeChoice.custom && widget.selected != TimeChoice.custom) {
      _reveal = true;
    }
    widget.onChanged(time, widget.custom.minutes, widget.custom.increment);
  }

  void _revealSteppers() {
    _reveal = false;
    final context = _steppers.currentContext;
    if (context == null) return;
    Scrollable.ensureVisible(
      context,
      alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : stepperRevealDuration,
      curve: Curves.easeOut,
    );
  }

  Widget _choice(TimeChoice time) => OptionButton(
    key: Key('${widget.keyPrefix}-time-${time.name}'),
    selected: widget.selected == time,
    onPressed: () => _choose(time),
    padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 8),
    radius: 11,
    look: OptionLook.setup,
    accent: widget.accent,
    child: Center(
      child: Text(
        time.label,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontFamily: Fonts.outfit,
          fontWeight: FontWeight.w600,
          fontSize: 12.5,
          height: 1,
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final custom = widget.custom;
    final showSteppers = widget.selected == TimeChoice.custom;
    if (showSteppers && _reveal) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _revealSteppers();
      });
    } else {
      _reveal = false;
    }
    final choices = TimeChoice.values;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < choices.length; i += 2) ...[
          if (i > 0) const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _choice(choices[i])),
              const SizedBox(width: 8),
              Expanded(
                child: i + 1 < choices.length
                    ? _choice(choices[i + 1])
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ],
        if (showSteppers)
          Padding(
            key: _steppers,
            padding: const EdgeInsets.only(top: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _StepperRow(
                  label: 'Minutes per side',
                  keyName: '${widget.keyPrefix}-minutes',
                  value: custom.minutes,
                  unit: 'min',
                  min: customMinutesMin,
                  max: customMinutesMax,
                  accent: widget.accent,
                  onStep: (v) => widget.onChanged(
                    widget.selected,
                    v,
                    widget.custom.increment,
                  ),
                ),
                const SizedBox(height: 9),
                _StepperRow(
                  label: 'Increment per move',
                  keyName: '${widget.keyPrefix}-increment',
                  value: custom.increment,
                  unit: 'sec',
                  min: customIncrementMin,
                  max: customIncrementMax,
                  accent: widget.accent,
                  onStep: (v) => widget.onChanged(
                    widget.selected,
                    widget.custom.minutes,
                    v,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// One stepper: its label, − and + around the value in [unit].
class _StepperRow extends StatelessWidget {
  const _StepperRow({
    required this.label,
    required this.keyName,
    required this.value,
    required this.unit,
    required this.min,
    required this.max,
    required this.accent,
    required this.onStep,
  });

  final String label;
  final String keyName;
  final int value;
  final String unit;
  final int min;
  final int max;
  final Accent accent;
  final ValueChanged<int> onStep;

  @override
  Widget build(BuildContext context) {
    final lower = label.toLowerCase();
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Palette.cardFill,
        borderRadius: BorderRadius.circular(11),
      ),
      // The buttons' touch areas take the design's gaps around the value
      // and most of its right padding, so they reach 48 dp while the drawn
      // boxes stay where the design puts them.
      child: Padding(
        padding: const EdgeInsets.only(left: 11, right: 1),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontFamily: Fonts.outfit,
                  fontWeight: FontWeight.w500,
                  fontSize: 11.5,
                  height: 1,
                  color: Palette.textChoice,
                ),
              ),
            ),
            _StepButton(
              key: Key('$keyName-dec'),
              glyph: '−',
              semantics: 'Decrease $lower',
              value: value,
              delta: -1,
              min: min,
              max: max,
              onStep: onStep,
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 50),
              child: Semantics(
                label: label,
                value: '$value $unit',
                child: ExcludeSemantics(
                  child: Text(
                    '$value $unit',
                    key: Key('$keyName-value'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: Fonts.plexMono,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      height: 1,
                      color: accent.text,
                    ),
                  ),
                ),
              ),
            ),
            _StepButton(
              key: Key('$keyName-inc'),
              glyph: '+',
              semantics: 'Increase $lower',
              value: value,
              delta: 1,
              min: min,
              max: max,
              onStep: onStep,
            ),
          ],
        ),
      ),
    );
  }
}

/// − or +: a tap steps once when the finger lifts; a press held for
/// [stepperHoldDelay] steps then, and every [stepperRepeat] after, until
/// release or the end. At the end it is drawn disabled and does nothing.
class _StepButton extends StatefulWidget {
  const _StepButton({
    super.key,
    required this.glyph,
    required this.semantics,
    required this.value,
    required this.delta,
    required this.min,
    required this.max,
    required this.onStep,
  });

  final String glyph;
  final String semantics;
  final int value;
  final int delta;
  final int min;
  final int max;
  final ValueChanged<int> onStep;

  static const drawn = 28.0;

  @override
  State<_StepButton> createState() => _StepButtonState();
}

class _StepButtonState extends State<_StepButton> {
  Timer? _repeat;

  /// The value as this hold has stepped it, ahead of the rebuild.
  int? _held;

  bool get _enabled {
    final next = widget.value + widget.delta;
    return next >= widget.min && next <= widget.max;
  }

  /// Steps from [from]; returns the new value, or null at the end.
  int? _step(int from) {
    final next = from + widget.delta;
    if (next < widget.min || next > widget.max) return null;
    widget.onStep(next);
    return next;
  }

  void _holdStart() {
    _held = _step(widget.value);
    if (_held == null) return;
    _repeat = Timer.periodic(stepperRepeat, (_) {
      final next = _step(_held!);
      if (next == null) {
        _stop();
      } else {
        _held = next;
      }
    });
  }

  void _stop() {
    _repeat?.cancel();
    _repeat = null;
    _held = null;
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = _enabled;
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.semantics,
      onTap: enabled ? () => _step(widget.value) : null,
      excludeSemantics: true,
      child: RawGestureDetector(
        behavior: HitTestBehavior.opaque,
        gestures: {
          TapGestureRecognizer:
              GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
                TapGestureRecognizer.new,
                (r) => r.onTap = () => _step(widget.value),
              ),
          LongPressGestureRecognizer:
              GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
                () => LongPressGestureRecognizer(duration: stepperHoldDelay),
                (r) {
                  r.onLongPressStart = (_) => _holdStart();
                  r.onLongPressEnd = (_) => _stop();
                  r.onLongPressCancel = _stop;
                },
              ),
        },
        child: SizedBox.square(
          dimension: OptionButton.minTouch,
          child: Center(
            child: Opacity(
              opacity: enabled ? 1 : disabledStepperOpacity,
              child: Container(
                width: _StepButton.drawn,
                height: _StepButton.drawn,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Palette.cardFill,
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: Palette.borderStrong),
                ),
                child: Text(
                  widget.glyph,
                  style: const TextStyle(
                    fontFamily: Fonts.outfit,
                    fontWeight: FontWeight.w500,
                    fontSize: 15,
                    height: 1,
                    color: Color(0xFFFFFFFF),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
