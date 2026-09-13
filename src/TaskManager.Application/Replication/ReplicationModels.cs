namespace TaskManager.Application.Replication;

/// <summary>
/// State of streaming replication seen from both servers.
/// </summary>
public class ReplicationStatus
{
    /// <summary>
    /// Gets or sets a value indicating whether a separate replica connection is configured.
    /// When it is not, reads go to the primary and everything else here is empty.
    /// </summary>
    public bool ReplicaConfigured { get; set; }

    /// <summary>
    /// Gets or sets the current WAL position of the primary (pg_current_wal_lsn).
    /// </summary>
    public string? PrimaryLsn { get; set; }

    /// <summary>
    /// Gets or sets a value indicating whether the replica answered and is in recovery mode.
    /// </summary>
    public bool ReplicaInRecovery { get; set; }

    /// <summary>
    /// Gets or sets the last WAL position received by the replica.
    /// </summary>
    public string? ReplicaReceiveLsn { get; set; }

    /// <summary>
    /// Gets or sets the last WAL position replayed by the replica.
    /// </summary>
    public string? ReplicaReplayLsn { get; set; }

    /// <summary>
    /// Gets or sets the commit time of the last transaction replayed by the replica.
    /// </summary>
    public DateTime? LastReplayAt { get; set; }

    /// <summary>
    /// Gets or sets how far the replica is behind the primary, in bytes of WAL.
    /// Zero means the replica has replayed everything the primary has written.
    /// </summary>
    public long? LagBytes { get; set; }

    /// <summary>
    /// Gets or sets how long ago the last replayed transaction was committed, in seconds.
    /// Without new writes this value grows even though the replica is up to date,
    /// so it is meaningful only together with <see cref="LagBytes"/>.
    /// </summary>
    public double? LagSeconds { get; set; }

    /// <summary>
    /// Gets or sets the rows of pg_stat_replication on the primary: one per connected replica.
    /// </summary>
    public List<ReplicaConnection> Connections { get; set; } = new();

    /// <summary>
    /// Gets or sets the error that prevented reading the state, if any.
    /// </summary>
    public string? Error { get; set; }
}

/// <summary>
/// One row of pg_stat_replication: a replica connected to the primary.
/// </summary>
public class ReplicaConnection
{
    /// <summary>
    /// Gets or sets the client address of the replica.
    /// </summary>
    public string? ClientAddr { get; set; }

    /// <summary>
    /// Gets or sets the application name reported by the replica.
    /// </summary>
    public string? ApplicationName { get; set; }

    /// <summary>
    /// Gets or sets the state of the WAL sender: "streaming" when the replica keeps up.
    /// </summary>
    public string? State { get; set; }

    /// <summary>
    /// Gets or sets the WAL position sent to the replica.
    /// </summary>
    public string? SentLsn { get; set; }

    /// <summary>
    /// Gets or sets the WAL position replayed by the replica.
    /// </summary>
    public string? ReplayLsn { get; set; }

    /// <summary>
    /// Gets or sets the time the primary waited for the replica to write the WAL, in seconds.
    /// </summary>
    public double? WriteLagSeconds { get; set; }

    /// <summary>
    /// Gets or sets the time the primary waited for the replica to flush the WAL, in seconds.
    /// </summary>
    public double? FlushLagSeconds { get; set; }

    /// <summary>
    /// Gets or sets the time the primary waited for the replica to replay the WAL, in seconds.
    /// </summary>
    public double? ReplayLagSeconds { get; set; }

    /// <summary>
    /// Gets or sets the WAL bytes sent to the replica but not replayed yet.
    /// </summary>
    public long? ReplayLagBytes { get; set; }

    /// <summary>
    /// Gets or sets the synchronization state: "async" for asynchronous replication.
    /// </summary>
    public string? SyncState { get; set; }
}

/// <summary>
/// Thresholds of the replica health check ("Replication" section).
/// </summary>
public class ReplicationOptions
{
    /// <summary>
    /// Configuration section name.
    /// </summary>
    public const string SectionName = "Replication";

    /// <summary>
    /// Gets or sets the replication lag in bytes of WAL above which the replica is reported as degraded.
    /// </summary>
    public long MaxLagBytes { get; set; } = 16 * 1024 * 1024;

    /// <summary>
    /// Gets or sets the age of the last replayed transaction, in seconds, that is reported
    /// as degraded when the replica is also behind by bytes.
    /// </summary>
    public double MaxLagSeconds { get; set; } = 30;
}
