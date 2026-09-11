namespace TaskManager.Application.Partitioning;

/// <summary>
/// A partition that should exist: values in [From, To) go to it.
/// </summary>
/// <param name="Name">The partition table name.</param>
/// <param name="From">Inclusive lower bound (UTC).</param>
/// <param name="To">Exclusive upper bound (UTC).</param>
public sealed record PartitionRange(string Name, DateTime From, DateTime To);

/// <summary>
/// A partition found in the database. Bounds are null for DEFAULT and non-time partitions.
/// </summary>
/// <param name="Name">The partition table name.</param>
/// <param name="From">Inclusive lower bound (UTC).</param>
/// <param name="To">Exclusive upper bound (UTC).</param>
public sealed record ExistingPartition(string Name, DateTime? From, DateTime? To);

/// <summary>
/// The last known result of the partition check for a table, used to avoid repeating the same alert.
/// </summary>
/// <param name="Table">The table name.</param>
/// <param name="Status">The status at the last check.</param>
/// <param name="MissingPartitions">Comma-separated missing partitions at the last check.</param>
/// <param name="ChangedAt">When the status or the list of missing partitions last changed (UTC).</param>
/// <param name="NotifiedAt">When an alert about the current state was sent; null if it was not delivered.</param>
public sealed record PartitionAlertState(
    string Table, PartitionStatus Status, string MissingPartitions, DateTime ChangedAt, DateTime? NotifiedAt);

/// <summary>
/// Result of the job or the check for one table.
/// </summary>
public class PartitionTableReport
{
    /// <summary>
    /// Gets or sets the table name.
    /// </summary>
    public string Table { get; set; } = string.Empty;

    /// <summary>
    /// Gets or sets the status of the table.
    /// </summary>
    public PartitionStatus Status { get; set; }

    /// <summary>
    /// Gets or sets the number of partitions found in the database.
    /// </summary>
    public int ExistingPartitions { get; set; }

    /// <summary>
    /// Gets or sets the partitions required for the current period and the horizon.
    /// </summary>
    public List<string> RequiredPartitions { get; set; } = new();

    /// <summary>
    /// Gets or sets the required partitions that were missing.
    /// </summary>
    public List<string> MissingPartitions { get; set; } = new();

    /// <summary>
    /// Gets or sets the partitions created by the job.
    /// </summary>
    public List<string> CreatedPartitions { get; set; } = new();

    /// <summary>
    /// Gets or sets the partitions dropped by the retention policy.
    /// </summary>
    public List<string> DroppedPartitions { get; set; } = new();

    /// <summary>
    /// Gets or sets what happened with the alert: "critical alert sent", "recovery sent",
    /// "already notified", "failed" or null when nothing had to be sent.
    /// </summary>
    public string? Alert { get; set; }

    /// <summary>
    /// Gets or sets the error message when the table could not be processed.
    /// </summary>
    public string? Error { get; set; }
}

/// <summary>
/// Result of one run of the job or the check.
/// </summary>
public class PartitionRunResult
{
    /// <summary>
    /// Gets or sets when the run happened (UTC).
    /// </summary>
    public DateTime CheckedAt { get; set; }

    /// <summary>
    /// Gets or sets the worst status among the tables.
    /// </summary>
    public PartitionStatus Status { get; set; }

    /// <summary>
    /// Gets or sets the per-table results.
    /// </summary>
    public List<PartitionTableReport> Tables { get; set; } = new();
}
