Feature: Morning Sync Immediate Settlement and Sleep-In Recalibration
  As a WHOOP 5.0 owner syncing right after waking up
  I want Today's Sleep and Recovery to settle as soon as live sync finishes and recalibrate if I go back to sleep
  So that I never wait 1.5–2 hours for morning metrics while still getting accurate scores after sleeping in

  Scenario: Completed morning sync past wake settles Sleep and Recovery immediately
    Given the user woke at 07:00 and HISTORY_COMPLETE arrived with data edge at 07:02
    When overnightSettled and recoveryStateOf evaluate the morning night
    Then overnightSettled is true and recoveryStateOf is finalReady without waiting 60 minutes

  Scenario: Mid-sleep background HISTORY_COMPLETE does not prematurely settle an ongoing sleep
    Given the user is still asleep at 04:04 when a background sync hits HISTORY_COMPLETE at 04:04
    When overnightSettled and recoveryStateOf evaluate the night
    Then overnightSettled is false and recoveryStateOf stays nightInProgress

  Scenario: Going back to sleep for an hour un-pins and recalibrates Today's Recovery
    Given 07:00 wake settled and pinned Today's Recovery at 74
    And a minor 10-minute wake jitter (+600s) keeps 74 pinned
    When the user goes back to sleep until 08:15 (+4500s) and syncs at 08:17
    Then nextFrozenHeadline and headlinePinFor recalibrate and re-pin Recovery to 81 at the 08:15 wake
