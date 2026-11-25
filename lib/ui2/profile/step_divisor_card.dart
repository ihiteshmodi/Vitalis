import 'package:flutter/material.dart';

import '../../data/step_calibration.dart'
    show
        clampStepDivisor,
        kDefaultStepDivisor,
        kMaxStepDivisor,
        kMinStepDivisor;
import '../../l10n/app_localizations.dart';
import '../../state/prefs.dart';
import '../ui2.dart';

class StepDivisorCard extends StatefulWidget {
  const StepDivisorCard({
    super.key,
    this.onChanged,
  });

  final ValueChanged<double>? onChanged;

  @override
  State<StepDivisorCard> createState() => _StepDivisorCardState();
}

class _StepDivisorCardState extends State<StepDivisorCard> {
  late double _current = clampStepDivisor(
    Prefs.getDouble(Prefs.stepDivisor, kDefaultStepDivisor),
  );
  late final TextEditingController _ctrl = TextEditingController(
    text: _formatDivisor(_current),
  );
  String? _error;

  static String _formatDivisor(double v) =>
      (v - v.roundToDouble()).abs() < 1e-6 && v == kDefaultStepDivisor
          ? v.toStringAsFixed(1)
          : (v * 10 == (v * 10).roundToDouble()
              ? v.toStringAsFixed(1)
              : v.toStringAsFixed(2));

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _apply() {
    final l = AppLocalizations.of(context);
    final raw = double.tryParse(_ctrl.text.trim().replaceAll(',', '.'));
    if (raw == null || !raw.isFinite || raw <= 0) {
      setState(() {
        _error = l?.stepDivisorInvalid ??
            'Enter a number between $kMinStepDivisor and $kMaxStepDivisor';
      });
      return;
    }
    final next = clampStepDivisor(raw);
    Prefs.setDouble(Prefs.stepDivisor, next);
    setState(() {
      _current = next;
      _ctrl.text = _formatDivisor(next);
      _error = null;
    });
    widget.onChanged?.call(next);
  }

  void _reset() {
    Prefs.setDouble(Prefs.stepDivisor, kDefaultStepDivisor);
    setState(() {
      _current = kDefaultStepDivisor;
      _ctrl.text = _formatDivisor(kDefaultStepDivisor);
      _error = null;
    });
    widget.onChanged?.call(kDefaultStepDivisor);
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final l = AppLocalizations.of(c);
    final shown = _formatDivisor(_current);
    return Surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l?.stepDivisorTitle ?? 'Band step divisor',
                      style: F.body.copyWith(
                        color: p.ink,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: S.x1),
                    Text(
                      l?.stepDivisorSub(shown) ??
                          'Active: $shown× · Divides walk/run band ticks ($kMinStepDivisor–$kMaxStepDivisor, default 1.0)',
                      style: F.cap.copyWith(color: p.ink3),
                    ),
                  ],
                ),
              ),
              if ((_current - kDefaultStepDivisor).abs() > 1e-6)
                TextButton(
                  onPressed: _reset,
                  child: Text(l?.stepDivisorReset ?? 'Reset'),
                ),
            ],
          ),
          const SizedBox(height: S.x3),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _ctrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  onSubmitted: (_) => _apply(),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: '1.0',
                    errorText: _error,
                  ),
                ),
              ),
              const SizedBox(width: S.x3),
              TextButton(
                onPressed: _apply,
                child: Text(l?.stepDivisorApply ?? 'Apply'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
