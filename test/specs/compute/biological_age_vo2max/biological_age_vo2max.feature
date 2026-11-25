Feature: Biological Age Suite (Body Age, Pace of Aging, Vitality, Fitness Age) and 3-Tier VO2max
  As a WHOOP 5.0 owner
  I want Body Age, Pace of Aging, Vitality, Fitness Age, and a 3-tier standing VO2max on Health and Today
  So that I can track long-term cardiorespiratory fitness and physiological aging honestly with zero fabricated numbers

  Scenario: VitalityEngine matches NOOP Gompertz hazard oracle and computes Pace of Aging
    Given an average 40-year-old peer vs a fitter 40-year-old with lower RHR, higher HRV, regular sleep, and 10,500 steps
    When VitalityEngine.compute evaluates both profiles
    Then the average peer lands at Body Age 40.0, Vitality 50.0, Pace 1.00x, and the fitter profile reads younger with Pace < 1.0x

  Scenario: 3-tier standing VO2max ladder selects Tier 1 GPS submax -> Tier 2 Nes waist -> Tier 3 Uth HR-ratio -> null
    Given combinations of workout submax VO2max, waist circumference, and 7-day RHR coverage
    When resolveStandingVo2max evaluates each case
    Then Tier 1 wins when submax exists, Tier 2 wins with waist + >=4 RHR nights, Tier 3 (15.3*HRmax/RHR) wins without waist, and <4 RHR nights abstains

  Scenario: HealthScreen and HomeScreen render BiologicalAgeCard with Body Age, Pace, Vitality, Fitness Age, and VO2max tier
    Given a populated LongevitySnapshot
    When HealthScreen and HomeScreen render
    Then Body Age, Pace of Aging, Vitality, Fitness Age, and VO2max tier label appear cleanly
