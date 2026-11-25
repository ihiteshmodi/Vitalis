Feature: NOOP Recovery Composite (55/20/15/5/5 EWMA + Logistic)
  As a WHOOP 5.0 owner
  I want Edge's headline Recovery score to use NOOP's 55% HRV / 20% RHR / 15% Sleep / 5% Resp / 5% Skin Temp Winsorized-EWMA + logistic formula starting on Night 5
  So that Recovery scores match NOOP's transparent physiological composite without a 14-night blank cold-start

  Scenario: Baseline-neutral night lands at NOOP's ~58% logistic anchor
    Given 4 prior nights at 90 ms HRV, 52 bpm RHR, 14.5 brpm Resp, and tonight matches with 85% sleep efficiency and 0.0 C temp delta
    When RecoveryScorer.scoreMetric evaluates tonight
    Then compositeZ is 0.0 and score is 57.932425 (100 / (1 + exp(-0.32)))

  Scenario: Cold-start gate withholds Nights 1-4 and publishes on Night 5
    Given the owner's real 6-night WHOOP 5.0 sequence (2026-10-08 to 2026-10-13)
    When deriveDayBundle and backfillNoopRecovery evaluate the sequence
    Then Nights 1-4 abstain with need_baseline:have=N,need=4 and Nights 5-6 publish real Recovery scores

  Scenario: Symmetric skin-temperature penalty and optional driver renormalization
    Given +0.8 C and -0.8 C skin temperature deviations on identical autonomic nights
    When RecoveryScorer.scoreMetric evaluates both nights
    Then both produce identical symmetric penalties lower than a 0.0 C night, and missing optional drivers renormalize cleanly
