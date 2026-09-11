namespace TaskManager.Application.Partitioning;

/// <summary>
/// Settings of the partition maintenance job and the partition health check ("Partitioning" section).
/// </summary>
public class PartitioningOptions
{
    /// <summary>
    /// Configuration section name.
    /// </summary>
    public const string SectionName = "Partitioning";

    /// <summary>
    /// Gets or sets a value indicating whether the background job and checks run.
    /// </summary>
    public bool Enabled { get; set; } = true;

    /// <summary>
    /// Gets or sets the time of day (UTC) when the nightly job creates future partitions.
    /// </summary>
    public TimeSpan JobTimeUtc { get; set; } = TimeSpan.FromHours(1);

    /// <summary>
    /// Gets or sets how often the partition health check runs.
    /// </summary>
    public TimeSpan CheckInterval { get; set; } = TimeSpan.FromMinutes(5);

    /// <summary>
    /// Gets or sets the partitioned tables to maintain.
    /// </summary>
    public List<PartitionedTableOptions> Tables { get; set; } = new();
}

/// <summary>
/// A table partitioned by a time column.
/// </summary>
public class PartitionedTableOptions
{
    /// <summary>
    /// Gets or sets the table name, optionally schema-qualified: "tasks", "lab03.events".
    /// </summary>
    public string Table { get; set; } = string.Empty;

    /// <summary>
    /// Gets or sets the size of one partition.
    /// </summary>
    public PartitionInterval Interval { get; set; } = PartitionInterval.Month;

    /// <summary>
    /// Gets or sets how many periods ahead must exist in addition to the current one.
    /// </summary>
    public int PeriodsAhead { get; set; } = 3;

    /// <summary>
    /// Gets or sets how many past periods to keep; older partitions are dropped. Null keeps everything.
    /// </summary>
    public int? RetentionPeriods { get; set; }
}
