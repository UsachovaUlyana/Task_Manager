using TaskManager.Application.Partitioning;

namespace TaskManager.Application.Interfaces;

/// <summary>
/// Access to partitions of partitioned tables and to the saved alert state.
/// </summary>
public interface IPartitionRepository
{
    /// <summary>
    /// Checks that the table exists and is partitioned.
    /// </summary>
    Task<bool> IsPartitionedAsync(string table, CancellationToken cancellationToken = default);

    /// <summary>
    /// Gets the partitions of the table with their bounds.
    /// </summary>
    Task<IReadOnlyList<ExistingPartition>> GetPartitionsAsync(string table, CancellationToken cancellationToken = default);

    /// <summary>
    /// Creates a partition; does nothing if a table with this name already exists.
    /// </summary>
    Task CreatePartitionAsync(string table, PartitionRange partition, CancellationToken cancellationToken = default);

    /// <summary>
    /// Detaches and drops a partition of the table.
    /// </summary>
    Task DropPartitionAsync(string table, string partitionName, CancellationToken cancellationToken = default);

    /// <summary>
    /// Gets the state saved by the previous check of the table.
    /// </summary>
    Task<PartitionAlertState?> GetAlertStateAsync(string table, CancellationToken cancellationToken = default);

    /// <summary>
    /// Saves the state of the table after a check.
    /// </summary>
    Task SaveAlertStateAsync(PartitionAlertState state, CancellationToken cancellationToken = default);
}
