namespace TaskManager.Application.Partitioning;

/// <summary>
/// Size of one partition of a time-partitioned table.
/// </summary>
public enum PartitionInterval
{
    /// <summary>
    /// One partition per day, for example events_2026_09_14.
    /// </summary>
    Day,

    /// <summary>
    /// One partition per month, for example tasks_2026_09.
    /// </summary>
    Month
}
