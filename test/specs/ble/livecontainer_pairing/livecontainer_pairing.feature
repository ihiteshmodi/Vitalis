Feature: LiveContainer Direct-Scan Pairing Fallback
  As a WHOOP 5.0 owner running Edge inside LiveContainer on iPhone 15 Pro Max
  I want to bypass iOS 18 AccessorySetupKit and scan directly over CoreBluetooth
  So that I can pair and bond my strap when the host container cannot attach ASK approval

  Scenario: ASK stays the default when supported and direct scan is off
    Given the platform supports AccessorySetupKit
    And direct Bluetooth scan mode is off
    When pairing decides which transport to use
    Then AccessorySetupKit picker is allowed

  Scenario: Direct Bluetooth scan overrides AccessorySetupKit inside LiveContainer
    Given the platform supports AccessorySetupKit
    When the user enables Direct Bluetooth scan mode
    Then AccessorySetupKit picker is skipped and direct service scan is used
    And flipping the switch is locked while a scan is in flight

  Scenario: One-tap fallback when ASK picker fails or is dismissed
    Given AccessorySetupKit failed with raw stage and error detail
    When the failure or cancelled pairing screen renders
    Then the raw error detail and stage are visible
    And tapping Pair with direct Bluetooth scan switches to scan mode and retries immediately
