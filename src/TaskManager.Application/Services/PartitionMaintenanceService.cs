using Microsoft.Extensions.Logging;
using TaskManager.Application.Interfaces;
using TaskManager.Application.Partitioning;

namespace TaskManager.Application.Services;

/// <summary>
/// CreatePartitionsJob and PartitionHealthCheck for time-partitioned tables.
/// </summary>
public class PartitionMaintenanceService : IPartitionMaintenanceService
{
    // The job creates one period more than the check requires: the horizon moves at midnight,
    // the nightly job runs later (JobTimeUtc), and in between the check must stay OK.
    private const int ReservePeriods = 1;

    private readonly IPartitionRepository _repository;
    private readonly IAlertNotifier _notifier;
    private readonly PartitioningOptions _options;
    private readonly TimeProvider _time;
    private readonly ILogger<PartitionMaintenanceService> _logger;

    /// <summary>
    /// Initializes a new instance of the <see cref="PartitionMaintenanceService"/> class.
    /// </summary>
    public PartitionMaintenanceService(
        IPartitionRepository repository,
        IAlertNotifier notifier,
        PartitioningOptions options,
        TimeProvider time,
        ILogger<PartitionMaintenanceService> logger)
    {
        _repository = repository;
        _notifier = notifier;
        _options = options;
        _time = time;
        _logger = logger;
    }

    /// <inheritdoc/>
    public async Task<PartitionRunResult> EnsurePartitionsAsync(CancellationToken cancellationToken = default)
    {
        var now = _time.GetUtcNow().UtcDateTime;
        var result = new PartitionRunResult { CheckedAt = now };
        _logger.LogInformation("Partition job started at {Now:yyyy-MM-dd HH:mm:ss} UTC", now);

        foreach (var table in _options.Tables)
        {
            var report = new PartitionTableReport { Table = table.Table };
            result.Tables.Add(report);

            try
            {
                var plan = await PlanAsync(table, table.PeriodsAhead + ReservePeriods, now, report, cancellationToken);
                if (plan is null)
                {
                    continue;
                }

                foreach (var partition in plan.Value.Missing)
                {
                    _logger.LogInformation("Creating partition {Partition}", partition.Name);
                    await _repository.CreatePartitionAsync(table.Table, partition, cancellationToken);
                    report.CreatedPartitions.Add(partition.Name);
                    _logger.LogInformation("Partition {Partition} created successfully", partition.Name);
                }

                if (table.RetentionPeriods is { } retention)
                {
                    foreach (var expired in PartitionPlanner.Expired(plan.Value.Existing, now, table.Interval, retention))
                    {
                        await _repository.DropPartitionAsync(table.Table, expired.Name, cancellationToken);
                        report.DroppedPartitions.Add(expired.Name);
                        _logger.LogInformation("Partition {Partition} is older than {Retention} periods and was dropped",
                            expired.Name, retention);
                    }
                }

                report.Status = PartitionStatus.Ok;
            }
            catch (Exception ex) when (ex is not OperationCanceledException)
            {
                report.Status = PartitionStatus.Critical;
                report.Error = ex.Message;
                _logger.LogError(ex, "Partition job failed for table {Table}", table.Table);
            }
        }

        result.Status = Worst(result.Tables);
        _logger.LogInformation("Partition job finished with status {Status}", result.Status);
        return result;
    }

    /// <inheritdoc/>
    public async Task<PartitionRunResult> CheckAsync(bool notify, CancellationToken cancellationToken = default)
    {
        var now = _time.GetUtcNow().UtcDateTime;
        var result = new PartitionRunResult { CheckedAt = now };

        foreach (var table in _options.Tables)
        {
            var report = new PartitionTableReport { Table = table.Table };
            result.Tables.Add(report);

            try
            {
                var plan = await PlanAsync(table, table.PeriodsAhead, now, report, cancellationToken);
                if (plan is null)
                {
                    continue;
                }

                report.Status = plan.Value.Missing.Count == 0 ? PartitionStatus.Ok : PartitionStatus.Critical;
                if (report.Status == PartitionStatus.Critical)
                {
                    _logger.LogWarning("Partition check CRITICAL for {Table}: missing {Missing}",
                        table.Table, string.Join(", ", report.MissingPartitions));
                }

                if (notify)
                {
                    report.Alert = await NotifyAsync(table, report, now, cancellationToken);
                }
            }
            catch (Exception ex) when (ex is not OperationCanceledException)
            {
                report.Status = PartitionStatus.Critical;
                report.Error = ex.Message;
                _logger.LogError(ex, "Partition check failed for table {Table}", table.Table);
            }
        }

        result.Status = Worst(result.Tables);
        return result;
    }

    private async Task<(IReadOnlyList<ExistingPartition> Existing, IReadOnlyList<PartitionRange> Missing)?> PlanAsync(
        PartitionedTableOptions table, int periodsAhead, DateTime now, PartitionTableReport report,
        CancellationToken cancellationToken)
    {
        if (!await _repository.IsPartitionedAsync(table.Table, cancellationToken))
        {
            report.Status = PartitionStatus.Skipped;
            _logger.LogWarning("Table {Table} does not exist or is not partitioned, skipped", table.Table);
            return null;
        }

        var existing = await _repository.GetPartitionsAsync(table.Table, cancellationToken);
        var required = PartitionPlanner.RequiredPartitions(table.Table, now, table.Interval, periodsAhead);
        var missing = PartitionPlanner.FindMissing(required, existing);

        report.ExistingPartitions = existing.Count;
        report.RequiredPartitions = required.Select(p => p.Name).ToList();
        report.MissingPartitions = missing.Select(p => p.Name).ToList();
        _logger.LogInformation(
            "Table {Table}: existing partitions {Existing}, required {Required}, missing {Missing}",
            table.Table, existing.Count, required.Count, missing.Count);

        return (existing, missing);
    }

    private async Task<string?> NotifyAsync(
        PartitionedTableOptions table, PartitionTableReport report, DateTime now, CancellationToken cancellationToken)
    {
        var missing = string.Join(", ", report.MissingPartitions);
        var previous = await _repository.GetAlertStateAsync(table.Table, cancellationToken);
        var action = AlertPolicy.Decide(previous, report.Status, missing);
        var changed = previous is null || previous.Status != report.Status || previous.MissingPartitions != missing;
        var changedAt = changed ? now : previous!.ChangedAt;

        if (action == AlertAction.None)
        {
            if (changed)
            {
                await _repository.SaveAlertStateAsync(
                    new PartitionAlertState(table.Table, report.Status, missing, changedAt, null), cancellationToken);
            }

            return report.Status == PartitionStatus.Critical ? "already notified" : null;
        }

        var message = action == AlertAction.SendCritical
            ? AlertMessages.Critical(table.Table, report.MissingPartitions,
                PartitionPlanner.Horizon(table.Interval, table.PeriodsAhead), now)
            : AlertMessages.Recovery(table.Table, now);

        try
        {
            await _notifier.SendAsync(message, cancellationToken);
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            _logger.LogError(ex, "Failed to send partition alert for {Table}", table.Table);

            // An undelivered CRITICAL is saved without NotifiedAt, so the next check sends it again.
            // An undelivered recovery keeps the old CRITICAL state, so the next check retries the recovery.
            if (action == AlertAction.SendCritical)
            {
                await _repository.SaveAlertStateAsync(
                    new PartitionAlertState(table.Table, report.Status, missing, changedAt, null), cancellationToken);
            }

            return "failed";
        }

        await _repository.SaveAlertStateAsync(
            new PartitionAlertState(table.Table, report.Status, missing, changedAt, now), cancellationToken);
        _logger.LogInformation("Partition {Action} sent for {Table}", action, table.Table);
        return action == AlertAction.SendCritical ? "critical alert sent" : "recovery sent";
    }

    private static PartitionStatus Worst(IEnumerable<PartitionTableReport> tables)
    {
        var statuses = tables.Select(t => t.Status).Where(s => s != PartitionStatus.Skipped).ToList();
        if (statuses.Count == 0)
        {
            return PartitionStatus.Skipped;
        }

        return statuses.Contains(PartitionStatus.Critical) ? PartitionStatus.Critical : PartitionStatus.Ok;
    }
}
