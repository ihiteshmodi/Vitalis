Feature: Walk/Run Activity-Class Step Filter and User-Configurable Step Divisor
  As a WHOOP 5.0 owner
  I want on-chip step deltas filtered to locomotion (activity_class 1=walk, 2=run) and scaled by a user-configurable divisor defaulting to 1.0
  So that non-walking wrist motion is excluded and I can tune my step divisor cleanly without hardcoded magic numbers

  Scenario: Walk/run filter excludes non-locomotion deltas and matches Oct 12 real DB oracle (25,179)
    Given WHOOP 5.0 1 Hz step_count and activity_class samples
    When counterDeltasFromSubstrate and hardwareStepSpansFromCounter evaluate the day
    Then only activity_class 1 and 2 deltas are credited (25,179 on 2026-10-12 vs 28,269 unfiltered), and substrates without activity_class keep all valid deltas

  Scenario: Step divisor defaults to 1.0 with zero hardcoding and clamps to [0.5, 30.0]
    Given raw walk/run ticks of 25,179
    When applyStepCalibration runs with default 1.0 vs userDivisor 2.5 and out-of-range inputs
    Then default yields 25,179, 2.5 yields 10,072, and clampStepDivisor clamps into [0.5, 30.0]

  Scenario: StepDivisorCard on MetricDetail('steps') edits, persists, and resets divisor
    Given MetricDetail('steps') on Today
    When the user saves divisor 2.5 and then taps Reset
    Then Prefs.stepDivisor updates to 2.5 and resets cleanly to 1.0
