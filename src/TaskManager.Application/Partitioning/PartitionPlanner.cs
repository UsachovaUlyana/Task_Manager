using System.Globalization;

namespace TaskManager.Application.Partitioning;

/// <summary>
/// Calculations for time-partitioned tables: which partitions must exist, which are missing
/// and which are older than the retention period. All times are UTC.
/// </summary>
public static class PartitionPlanner
{
    /// <summary>
    /// Gets the start of the period that contains the moment.
    /// </summary>
    public static DateTime PeriodStart(DateTime moment, PartitionInterval interval)
    {
        var utc = moment.Kind == DateTimeKind.Local ? moment.ToUniversalTime() : moment;
        return interval == PartitionInterval.Day
            ? new DateTime(utc.Year, utc.Month, utc.Day, 0, 0, 0, DateTimeKind.Utc)
            : new DateTime(utc.Year, utc.Month, 1, 0, 0, 0, DateTimeKind.Utc);
    }

    /// <summary>
    /// Moves a period start by the given number of periods.
    /// </summary>
    public static DateTime AddPeriods(DateTime start, PartitionInterval interval, int periods) =>
        interval == PartitionInterval.Day ? start.AddDays(periods) : start.AddMonths(periods);

    /// <summary>
    /// Builds the partition name: events_2026_09_14 for days, tasks_2026_09 for months.
    /// The schema of a qualified table name is not part of the partition name.
    /// </summary>
    public static string PartitionName(string table, DateTime start, PartitionInterval interval)
    {
        var baseName = table[(table.LastIndexOf('.') + 1)..];
        var suffix = start.ToString(interval == PartitionInterval.Day ? "yyyy_MM_dd" : "yyyy_MM", CultureInfo.InvariantCulture);
        return $"{baseName}_{suffix}";
    }

    /// <summary>
    /// Gets the partitions that must exist: the current period and <paramref name="periodsAhead"/> periods after it.
    /// </summary>
    public static IReadOnlyList<PartitionRange> RequiredPartitions(
        string table, DateTime now, PartitionInterval interval, int periodsAhead)
    {
        var first = PeriodStart(now, interval);
        return Enumerable.Range(0, periodsAhead + 1)
            .Select(i =>
            {
                var from = AddPeriods(first, interval, i);
                return new PartitionRange(PartitionName(table, from, interval), from, AddPeriods(from, interval, 1));
            })
            .ToList();
    }

    /// <summary>
    /// Gets the required partitions whose range is not covered by an existing partition.
    /// Coverage is checked by bounds, not by name, so a partition with another name still counts.
    /// </summary>
    public static IReadOnlyList<PartitionRange> FindMissing(
        IEnumerable<PartitionRange> required, IEnumerable<ExistingPartition> existing)
    {
        var ranges = existing.Where(p => p.From.HasValue && p.To.HasValue).ToList();
        return required.Where(r => !ranges.Any(p => p.From <= r.From && p.To >= r.To)).ToList();
    }

    /// <summary>
    /// Gets the partitions that end before the retention boundary.
    /// </summary>
    public static IReadOnlyList<ExistingPartition> Expired(
        IEnumerable<ExistingPartition> existing, DateTime now, PartitionInterval interval, int retentionPeriods)
    {
        var boundary = AddPeriods(PeriodStart(now, interval), interval, -retentionPeriods);
        return existing.Where(p => p.To.HasValue && p.To <= boundary).ToList();
    }

    /// <summary>
    /// Describes the horizon for the alert text: "3 days", "3 months".
    /// </summary>
    public static string Horizon(PartitionInterval interval, int periodsAhead) =>
        $"{periodsAhead} {(interval == PartitionInterval.Day ? "days" : "months")}";
}
