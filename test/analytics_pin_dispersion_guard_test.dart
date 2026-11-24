// M5 §0.2/§17: the baseline-dispersion-below-quantum guard in
// readiness_composite.dart is a genuine prerequisite for any cross-device
// masking of readiness's inputs. It ships in the vendored analytics copy
// (packages/openstrap_analytics, pinned in packages/PINS.txt). This is the
// reachability proof that a future repin or re-vendor cannot silently drop it.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the vendored analytics contains the baseline-dispersion-below-quantum '
      'guard in readiness_composite.dart', () {
    final source = File(
      'packages/openstrap_analytics/lib/src/onehz/wellness/readiness_composite.dart',
    ).readAsStringSync();
    expect(
      source.contains('baseline_dispersion_below_quantum'),
      isTrue,
      reason: 'the vendored analytics no longer contains the dispersion guard '
          'readiness_composite.dart needs before M5\'s masking can safely '
          'apply to readiness inputs. A repin or re-vendor silently DROPPED it.',
    );
  });
}
