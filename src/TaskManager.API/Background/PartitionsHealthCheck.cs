using Microsoft.Extensions.Diagnostics.HealthChecks;
using TaskManager.Application.Interfaces;
using TaskManager.Application.Partitioning;

namespace TaskManager.API.Background;

/// <summary>
/// GET /health/partitions: Unhealthy when a partition required for the horizon is missing.
/// Only reports the state; alerts are sent by <see cref="PartitionMaintenanceWorker"/>.
/// </summary>
public class PartitionsHealthCheck : IHealthCheck
{
    private readonly IServiceScopeFactory _scopeFactory;

    /// <summary>
    /// Initializes a new instance of the <see cref="PartitionsHealthCheck"/> class.
    /// </summary>
    public PartitionsHealthCheck(IServiceScopeFactory scopeFactory)
    {
        _scopeFactory = scopeFactory;
    }

    /// <inheritdoc/>
    public async Task<HealthCheckResult> CheckHealthAsync(HealthCheckContext context, CancellationToken cancellationToken = default)
    {
        using var scope = _scopeFactory.CreateScope();
        var service = scope.ServiceProvider.GetRequiredService<IPartitionMaintenanceService>();
        var result = await service.CheckAsync(notify: false, cancellationToken);

        var data = result.Tables.ToDictionary(
            t => t.Table,
            t => (object)(t.MissingPartitions.Count == 0
                ? t.Status.ToString()
                : $"{t.Status}: missing {string.Join(", ", t.MissingPartitions)}"));

        return result.Status == PartitionStatus.Critical
            ? HealthCheckResult.Unhealthy("Some required partitions are missing", data: data)
            : HealthCheckResult.Healthy("All required partitions exist", data);
    }
}
