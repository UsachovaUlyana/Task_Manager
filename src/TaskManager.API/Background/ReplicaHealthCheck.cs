using Microsoft.Extensions.Diagnostics.HealthChecks;
using TaskManager.Application.Interfaces;
using TaskManager.Application.Replication;

namespace TaskManager.API.Background;

/// <summary>
/// GET /health/replica: whether the replica answers, is in recovery mode and how far behind it is.
/// </summary>
public class ReplicaHealthCheck : IHealthCheck
{
    private readonly IServiceScopeFactory _scopeFactory;
    private readonly ReplicationOptions _options;

    /// <summary>
    /// Initializes a new instance of the <see cref="ReplicaHealthCheck"/> class.
    /// </summary>
    public ReplicaHealthCheck(IServiceScopeFactory scopeFactory, ReplicationOptions options)
    {
        _scopeFactory = scopeFactory;
        _options = options;
    }

    /// <inheritdoc/>
    public async Task<HealthCheckResult> CheckHealthAsync(
        HealthCheckContext context, CancellationToken cancellationToken = default)
    {
        using var scope = _scopeFactory.CreateScope();
        var monitor = scope.ServiceProvider.GetRequiredService<IReplicationMonitor>();
        var status = await monitor.GetStatusAsync(cancellationToken);

        var data = new Dictionary<string, object>
        {
            ["replicaConfigured"] = status.ReplicaConfigured,
            ["primaryLsn"] = status.PrimaryLsn ?? "-",
            ["replicaReplayLsn"] = status.ReplicaReplayLsn ?? "-",
            ["lagBytes"] = status.LagBytes ?? -1,
            ["lagSeconds"] = status.LagSeconds ?? -1,
            ["connections"] = status.Connections.Count
        };

        if (status.Error is not null)
        {
            return HealthCheckResult.Unhealthy($"Replication state is unavailable: {status.Error}", data: data);
        }

        if (!status.ReplicaConfigured)
        {
            return HealthCheckResult.Healthy("No replica is configured, reads go to the primary", data);
        }

        if (!status.ReplicaInRecovery)
        {
            return HealthCheckResult.Unhealthy("The replica is not in recovery mode", data: data);
        }

        // Without writes on the primary the age of the last transaction grows on its own,
        // so "behind" means behind in WAL bytes and in time at once
        var behind = (status.LagBytes ?? 0) > _options.MaxLagBytes
                     && (status.LagSeconds ?? 0) > _options.MaxLagSeconds;

        return behind
            ? HealthCheckResult.Degraded($"The replica is behind by {status.LagBytes} bytes of WAL", data: data)
            : HealthCheckResult.Healthy("The replica is streaming", data);
    }
}
