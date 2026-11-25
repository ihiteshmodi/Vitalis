Feature: Battery History Chart and Drain Forecast UI
  As a WHOOP 5.0 owner checking my band's battery health and runtime
  I want a 24h / 7d / 30d battery percentage chart with charge markers and Theil-Sen drain rate on Device Detail
  So that I can see historical discharge curves, charge events, and honest remaining runtime without fabricated numbers

  Scenario: Dense battery series preserves unmeasured gaps and marks charge transitions
    Given battery samples across a 24h window with a 4-hour unmeasured gap and a charger session
    When buildBatteryHistorySeries buckets the 24h window
    Then unmeasured buckets stay null and a single charge mark is emitted at the charger transition

  Scenario: 30-day DB query returns full window without 400-row truncation
    Given 650 band_battery rows spanning 10 days
    When bandBatterySamplesSince queries the last 30 days
    Then all 650 samples with non-null battery_pct are returned in ascending timestamp order

  Scenario: DeviceDetailView renders 24h/7d/30d tabs, drain rate, and honest abstention
    Given DeviceDetailView with battery samples and a usable BatteryForecast
    When rendered and switched across 24h, 7d, and 30d tabs
    Then the chart switches ranges, shows %/hr and %/day drain rate, and abstains cleanly when charging
