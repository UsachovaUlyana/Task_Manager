using TaskManager.Application.Interfaces;
using TaskManager.Application.Partitioning;

namespace TaskManager.API.Background;

/// <summary>
/// Runs the partition job at startup and every night at <see cref="PartitioningOptions.JobTimeUtc"/>,
/// and the partition health check (with alerts) every <see cref="PartitioningOptions.CheckInterval"/>.
/// </summary>
public class PartitionMaintenanceWorker : BackgroundService
{
    private readonly IServiceScopeFactory _scopeFactory;
    private readonly PartitioningOptions _options;
    private readonly TimeProvider _time;
    private readonly ILogger<PartitionMaintenanceWorker> _logger;

    /// <summary>
    /// Initializes a new instance of the <see cref="PartitionMaintenanceWorker"/> class.
    /// </summary>
    public PartitionMaintenanceWorker(
        IServiceScopeFactory scopeFactory,
        PartitioningOptions options,
        TimeProvider time,
        ILogger<PartitionMaintenanceWorker> logger)
    {
        _scopeFactory = scopeFactory;
        _options = options;
        _time = time;
        _logger = logger;
    }

    /// <inheritdoc/>
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        if (!_options.Enabled)
        {
            _logger.LogInformation("Partition maintenance is disabled");
            return;
        }

        var lastJobDay = DateOnly.FromDateTime(_time.GetUtcNow().UtcDateTime);
        await RunAsync(service => service.EnsurePartitionsAsync(stoppingToken), "job");
        await RunAsync(service => service.CheckAsync(notify: true, stoppingToken), "check");

        using var timer = new PeriodicTimer(_options.CheckInterval, _time);
        while (await timer.WaitForNextTickAsync(stoppingToken))
        {
            var now = _time.GetUtcNow().UtcDateTime;
            var today = DateOnly.FromDateTime(now);
            if (today != lastJobDay && now.TimeOfDay >= _options.JobTimeUtc)
            {
                lastJobDay = today;
                await RunAsync(service => service.EnsurePartitionsAsync(stoppingToken), "job");
            }

            await RunAsync(service => service.CheckAsync(notify: true, stoppingToken), "check");
        }
    }

    private async Task RunAsync(Func<IPartitionMaintenanceService, Task> action, string name)
    {
        try
        {
            using var scope = _scopeFactory.CreateScope();
            await action(scope.ServiceProvider.GetRequiredService<IPartitionMaintenanceService>());
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            // The worker must survive a failed run: the next tick tries again
            _logger.LogError(ex, "Partition {Run} failed", name);
        }
    }
}
