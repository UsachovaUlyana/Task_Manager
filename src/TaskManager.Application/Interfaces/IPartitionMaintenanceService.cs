using TaskManager.Application.Partitioning;

namespace TaskManager.Application.Interfaces;

/// <summary>
/// The partition maintenance job and the partition health check.
/// </summary>
public interface IPartitionMaintenanceService
{
    /// <summary>
    /// Creates missing partitions for the current period and the horizon and drops expired ones.
    /// Safe to run repeatedly: existing partitions are not touched.
    /// </summary>
    Task<PartitionRunResult> EnsurePartitionsAsync(CancellationToken cancellationToken = default);

    /// <summary>
    /// Checks that all required partitions exist and, if <paramref name="notify"/> is set,
    /// sends an alert on a new problem and a recovery message when it is fixed.
    /// </summary>
    Task<PartitionRunResult> CheckAsync(bool notify, CancellationToken cancellationToken = default);
}
