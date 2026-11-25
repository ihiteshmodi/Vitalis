Feature: Full Overnight 5-Minute HRV Curve and Stats on Main Screens
  As a WHOOP 5.0 owner checking HRV and Sleep
  I want the full overnight 5-minute HRV curve and Min / Median / Mean / Max / SDNN stats directly on HRV Detail and Sleep Detail
  So that I can inspect overnight autonomic recovery immediately without digging into Advanced screens

  Scenario: Dense 5-minute overnight HRV bucketer preserves gaps and computes Min/Median/Mean/Max/SDNN
    Given overnight 5-minute HRV samples with a 30-minute middle gap, headline mean 91 ms, and SDNN 84 ms
    When computeOvernightHrvStats evaluates the night
    Then middle gap buckets stay null and Min, Median, Mean, Max, and SDNN match exact values

  Scenario: MetricDetail('hrv') renders OvernightHrvCard directly on the main screen
    Given MetricData for hrv carrying overnightHrv timeline and SDNN
    When MetricDetail('hrv') renders
    Then OvernightHrvCard displays the overnight curve plus Min, Median, Mean, Max, and SDNN

  Scenario: SleepDetail renders OvernightHrvCard directly on the main Sleep screen
    Given SleepData with a scored night and overnightHrv timeline + SDNN
    When SleepDetail renders
    Then OvernightHrvCard displays the overnight curve plus Min, Median, Mean, Max, and SDNN without bare dashes
