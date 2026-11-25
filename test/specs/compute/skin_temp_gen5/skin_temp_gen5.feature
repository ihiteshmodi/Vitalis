Feature: WHOOP 5.0 Exact Skin Temperature, Warm-Up Settle Band, and Wear-Site Baseline Scoping
  As a WHOOP 5.0 owner wearing the band on my wrist or upper arm
  I want exact nightly °C/°F skin temperature from Night 1, warm-up sample trimming, 4th-night usual deviation, and wrist/bicep baseline isolation
  So that Vitals and Skin Temperature detail show accurate, unpolluted readings in my chosen unit

  Scenario: Gen5 nightlySkinTemp trims cold warm-up samples and preserves fevers
    Given a WHOOP 5.0 sleep window in centi-C around 33.40 C with a 5% cold 30.00 C warm-up segment
    When nightlySkinTemp evaluates deviceFamily gen5
    Then settledFraction is 0.95 and the settled mean is 3340.0 centi-C without cold-segment drag

  Scenario: Night 1 emits exact skin_temp_c and Night 4 emits skin_temp_dev_c
    Given WHOOP 5.0 sleep samples at 33.60 C and 3 prior wrist nights [33.20, 33.30, 33.40] C
    When computeDayBundle runs for gen5
    Then scalars.skin_temp_c is 33.6 and scalars.skin_temp_dev_c is +0.3

  Scenario: Wrist and Bicep wear sites keep separate skin temperature baselines
    Given 3 prior Wrist nights around 33.3 C and 3 prior Bicep nights around 34.4 C
    When baseline history is resolved for Wrist vs Bicep
    Then Wrist sees only Wrist nights and Bicep sees only Bicep nights

  Scenario: Vitals and MetricDetail render exact C and F with usual delta and trend chart
    Given HealthScreen Vitals with abs_c 33.6 and dev_c +0.3
    When rendered in Metric and Imperial units
    Then Metric shows 33.6 °C with +0.3 °C vs your usual, Imperial shows 92.5 °F with +0.5 °F vs your usual, and MetricDetail('skin_temp') is unsuppressed
