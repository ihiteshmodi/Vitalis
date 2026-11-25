Feature: Sync Progress Card and Live BLE Log Sheet
  As a WHOOP 5.0 owner waiting on a multi-minute history sync
  I want to see live chunk counts, backlog at connect, and a tappable BLE log sheet without fabricated percentages
  So that I can tell immediately whether sync is moving, finished, or disconnected

  Scenario: Backlog snapshot at connect computes wrap-safe pages behind and never invents a percent
    Given GET_DATA_RANGE reported written page 150, trim page 108, and capacity 131072
    When SyncProgressSnapshot computes pagesBehindAtConnect
    Then pagesBehindAtConnect is 42
    And no percentage complete is ever computed or rendered

  Scenario: Live chunk count increments on ACK and resets cleanly on sync start and disconnect
    Given a sync starts and ACKs 3 historical chunks
    When SyncProgressSnapshot updates after each ACK and then the link drops
    Then chunksPulled rises 0 -> 1 -> 2 -> 3 during sync and resets to 0 on disconnect

  Scenario: Tapping Home sync progress card opens the Live BLE Log & Sync Status sheet
    Given Home renders the syncing phase card with 14 chunks pulled and 42 pages behind at connect
    When the user taps the Sync card
    Then the Sync Status & Live BLE Log sheet opens showing chunk count, backlog snapshot, Sync Now state, and BLE log lines
