Feature: Backup and Restore Sync Reconciliation
  As an OpenStrap Edge user restoring a database backup after a multi-day gap
  I want cursors, RR beats, and live sync burst policies to reconcile cleanly
  So that new strap history after the backup timestamp syncs and derives without stalling

  Scenario: Stale strap_trim is never imported and monotonic cursors advance to max
    Given a local install has an older rec_ts_hw cursor and a backup has a newer rec_ts_hw and a stale strap_trim
    When the backup database is imported
    Then strap_trim is not imported from the backup
    And rec_ts_hw and counter_hw advance to the higher plausible cursor

  Scenario: Corrupt future rec_ts_hw in backup is rejected so sync burst is never poisoned
    Given a backup carries an implausible future rec_ts_hw cursor
    When the backup database is imported alongside plausible decoded_onehz rows
    Then rec_ts_hw reconciles to the plausible decoded_onehz high-water instead of the future timestamp

  Scenario: Replacing a 1 Hz second recorded off-skin (hr = 0) clears stale local RR beats
    Given a local install holds RR beats at second T
    And a backup carries a decoded_onehz row at second T with hr = 0 and no decoded_rr rows
    When the backup database is imported
    Then the stale local RR beats at second T are cleared on both bulk and row-by-row merge paths

  Scenario: Sync burst continues through pre-backup overlap chunks when strapNewest is unknown
    Given a sync session ACKed batches of overlap records older than rec_ts_hw and has not reported HISTORY_COMPLETE
    And GET_DATA_RANGE newest timestamp is null
    When SyncController evaluates whether to continue the backfill burst
    Then the burst continues draining through the overlap to reach post-backup records
