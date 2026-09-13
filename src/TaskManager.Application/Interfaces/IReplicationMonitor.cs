using TaskManager.Application.Replication;

namespace TaskManager.Application.Interfaces;

/// <summary>
/// Reads the state of streaming replication from the primary and the replica.
/// </summary>
public interface IReplicationMonitor
{
    /// <summary>
    /// Gets the current replication state, including the lag of the replica.
    /// </summary>
    Task<ReplicationStatus> GetStatusAsync(CancellationToken cancellationToken = default);
}
