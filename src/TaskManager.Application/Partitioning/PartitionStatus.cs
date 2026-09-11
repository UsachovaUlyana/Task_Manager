using System.Text.Json.Serialization;

namespace TaskManager.Application.Partitioning;

/// <summary>
/// Result of a partition check for one table.
/// </summary>
[JsonConverter(typeof(JsonStringEnumConverter))]
public enum PartitionStatus
{
    /// <summary>
    /// All partitions required for the horizon exist.
    /// </summary>
    Ok,

    /// <summary>
    /// At least one required partition is missing: inserts for that period will fail.
    /// </summary>
    Critical,

    /// <summary>
    /// The table does not exist or is not partitioned, so it was not checked.
    /// </summary>
    Skipped
}
