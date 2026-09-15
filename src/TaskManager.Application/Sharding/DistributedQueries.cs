using TaskManager.Domain.Entities;
using TaskManager.Domain.Enums;

namespace TaskManager.Application.Sharding;

/// <summary>
/// Partial aggregate of one shard: enough to merge exactly (sums and counts, not averages).
/// </summary>
/// <param name="Status">The task status.</param>
/// <param name="Count">Tasks with the status.</param>
/// <param name="Overdue">Overdue tasks among them.</param>
/// <param name="AgeDaysSum">Sum of task ages in days, to compute the average after the merge.</param>
public sealed record StatusAggregate(int Status, long Count, long Overdue, double AgeDaysSum);

/// <summary>
/// How one shard answered a distributed query.
/// </summary>
/// <param name="Shard">The shard number.</param>
/// <param name="Available">Whether the shard answered.</param>
/// <param name="Rows">Rows the shard sent to the service.</param>
/// <param name="Milliseconds">How long the shard took, including the connection.</param>
/// <param name="Error">The reason when the shard did not answer.</param>
public sealed record ShardCall(int Shard, bool Available, long Rows, double Milliseconds, string? Error = null);

/// <summary>
/// Merged value of one status.
/// </summary>
/// <param name="Status">The task status.</param>
/// <param name="Count">Tasks with the status on all answered shards.</param>
/// <param name="Overdue">Overdue tasks.</param>
/// <param name="AverageAgeDays">Correct average age: total sum divided by total count.</param>
/// <param name="AverageOfShardAveragesDays">Wrong average: plain mean of shard averages, shown for comparison.</param>
public sealed record StatusStat(string Status, long Count, long Overdue, double AverageAgeDays, double AverageOfShardAveragesDays);

/// <summary>
/// Common part of every distributed query result.
/// </summary>
public abstract class DistributedResult
{
    /// <summary>Gets or sets how each shard answered.</summary>
    public List<ShardCall> Shards { get; set; } = new();

    /// <summary>Gets or sets a value indicating whether some shards did not answer and the result is incomplete.</summary>
    public bool Partial { get; set; }

    /// <summary>Gets or sets the total time of the request in the service, in milliseconds.</summary>
    public double TotalMilliseconds { get; set; }
}

/// <summary>
/// COUNT and AVG by status over all shards.
/// </summary>
public class DistributedStats : DistributedResult
{
    /// <summary>Gets or sets a value indicating whether the shards were queried in parallel.</summary>
    public bool Parallel { get; set; }

    /// <summary>Gets or sets the merged values by status.</summary>
    public List<StatusStat> Statuses { get; set; } = new();

    /// <summary>Gets or sets the number of tasks per shard, before the merge.</summary>
    public Dictionary<string, long> TasksPerShard { get; set; } = new();

    /// <summary>Gets or sets all tasks on the answered shards.</summary>
    public long Total { get; set; }
}

/// <summary>
/// A page of the newest tasks over all shards: ORDER BY created_at DESC LIMIT.
/// </summary>
public class DistributedPage : DistributedResult
{
    /// <summary>Gets or sets the page number.</summary>
    public int Page { get; set; }

    /// <summary>Gets or sets the page size.</summary>
    public int PageSize { get; set; }

    /// <summary>Gets or sets how many rows each shard had to return: OFFSET + LIMIT.</summary>
    public int RowsRequestedPerShard { get; set; }

    /// <summary>Gets or sets the page after the merge.</summary>
    public List<ShardedTaskRow> Items { get; set; } = new();
}

/// <summary>
/// The user's tasks from their shard joined with project names from the main database in the service.
/// </summary>
public class DistributedJoin : DistributedResult
{
    /// <summary>Gets or sets the shard of the user.</summary>
    public int Shard { get; set; }

    /// <summary>Gets or sets the user name read from the main database.</summary>
    public string? Username { get; set; }

    /// <summary>Gets or sets the steps of the join and their cost.</summary>
    public List<JoinStep> Steps { get; set; } = new();

    /// <summary>Gets or sets the joined rows.</summary>
    public List<TaskWithProject> Items { get; set; } = new();
}

/// <summary>
/// One round trip of an application-side join.
/// </summary>
/// <param name="Database">Where the query went.</param>
/// <param name="Query">What was asked.</param>
/// <param name="Rows">Rows transferred to the service.</param>
/// <param name="Milliseconds">How long it took.</param>
public sealed record JoinStep(string Database, string Query, long Rows, double Milliseconds);

/// <summary>
/// A task row with the shard it came from.
/// </summary>
public sealed record ShardedTaskRow(int Shard, Guid Id, Guid UserId, string Title, string Status, DateTime CreatedAt);

/// <summary>
/// A task joined with its project.
/// </summary>
public sealed record TaskWithProject(Guid Id, string Title, string Status, DateTime CreatedAt, Guid? ProjectId, string? ProjectName);

/// <summary>
/// Pure merge logic of distributed queries.
/// </summary>
public static class DistributedMerge
{
    /// <summary>
    /// Merges per-shard aggregates: counts and sums are added, the average is computed from the totals.
    /// </summary>
    public static List<StatusStat> MergeStatuses(IReadOnlyCollection<IReadOnlyList<StatusAggregate>> shards)
    {
        return shards
            .SelectMany(s => s)
            .GroupBy(a => a.Status)
            .OrderBy(g => g.Key)
            .Select(g =>
            {
                var count = g.Sum(a => a.Count);
                return new StatusStat(
                    ((TaskItemStatus)g.Key).ToString(),
                    count,
                    g.Sum(a => a.Overdue),
                    count == 0 ? 0 : Math.Round(g.Sum(a => a.AgeDaysSum) / count, 3),
                    Math.Round(g.Where(a => a.Count > 0).Average(a => a.AgeDaysSum / a.Count), 3));
            })
            .ToList();
    }

    /// <summary>
    /// Merges the newest rows of every shard into one global order and cuts the requested page.
    /// Every shard must have returned at least <paramref name="skip"/> + <paramref name="take"/> rows.
    /// </summary>
    public static List<ShardedTaskRow> MergeNewest(
        IEnumerable<(int Shard, IReadOnlyList<TaskItem> Rows)> shards, int skip, int take)
    {
        return shards
            .SelectMany(s => s.Rows.Select(t => new ShardedTaskRow(s.Shard, t.Id, t.UserId, t.Title, t.Status.ToString(), t.CreatedAt)))
            .OrderByDescending(r => r.CreatedAt)
            .ThenByDescending(r => r.Id)
            .Skip(skip)
            .Take(take)
            .ToList();
    }
}
