Feature: Restart Band and Post-Reboot Overwrite Re-Derivation
  As a WHOOP 5.0 owner troubleshooting a wedged sensor or BLE link
  I want to restart my strap safely from Band Settings and automatically re-derive any overwritten past days
  So that I can recover my strap without losing data or leaving stale finalized scores behind

  Scenario: Confirmed band restart sends opcode 0x1D with empty payload on Gen5
    Given a connected WHOOP 5.0 session with no active history offload
    When rebootStrap is invoked by explicit user action
    Then opcode 0x1D (29) is transmitted with an empty body while dangerousCmds still blocks unapproved writes

  Scenario: Restart is refused when disconnected or while an offload is active
    Given the band is disconnected or actively draining history chunks
    When rebootStrap is invoked or DeviceDetailView renders
    Then no frame is transmitted and the Restart row explains why it is unavailable

  Scenario: Post-reboot 3-day history re-offload un-finalizes touched days and re-derives them
    Given a day 3 days ago was already marked finalized = 1 with a cached derive_fingerprint
    When commitSyncBatch persists newly re-offloaded 1 Hz rows for that day
    Then that day's finalized flag resets to 0 and its derive_fingerprint is cleared so heavy derivation recomputes it
