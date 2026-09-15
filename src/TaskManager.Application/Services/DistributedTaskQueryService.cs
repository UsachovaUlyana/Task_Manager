using System.Diagnostics;
using Microsoft.Extensions.Logging;
using TaskManager.Application.Exceptions;
using TaskManager.Application.Interfaces;
using TaskManager.Application.Sharding;

namespace TaskManager.Application.Services;

/// <summary>
/// Scatter-gather over task shards: the query is sent to the needed shards, the service merges the answers.
/// </summary>
public class DistributedTaskQueryService : IDistributedTaskQueryService
{
    private readonly IShardedTaskStore _store;
    private readonly ILogger<DistributedTaskQueryService> _logger;

    /// <summary>
    /// Initializes a new instance of the <see cref="DistributedTaskQueryService"/> class.
    /// </summary>
    public DistributedTaskQueryService(IShardedTaskStore store, ILogger<DistributedTaskQueryService> logger)
    {
        _store = store;
        _logger = logger;
    }

    /// <inheritdoc/>
    public async Task<DistributedStats> GetStatsAsync(bool parallel, bool allowPartial, CancellationToken cancellationToken = default)
    {
        var total = Stopwatch.StartNew();
        var now = DateTime.UtcNow;
        var shards = await ActiveShardsAsync(cancellationToken);
        var answers = await ScatterAsync(
            shards, parallel, allowPartial,
            (shard, ct) => _store.AggregateByStatusAsync(shard, now, ct),
            rows => rows.Count,
            cancellationToken);

        var aggregates = answers.Results.Select(r => r.Value).ToList();
        return new DistributedStats
        {
            Parallel = parallel,
            Shards = answers.Calls,
            Partial = answers.Calls.Any(c => !c.Available),
            Statuses = DistributedMerge.MergeStatuses(aggregates),
            TasksPerShard = answers.Results.ToDictionary(r => $"shard-{r.Shard}", r => r.Value.Sum(a => a.Count)),
            Total = aggregates.Sum(a => a.Sum(x => x.Count)),
            TotalMilliseconds = Elapsed(total)
        };
    }

    /// <inheritdoc/>
    public async Task<DistributedPage> GetNewestAsync(int page, int pageSize, bool allowPartial, CancellationToken cancellationToken = default)
    {
        var total = Stopwatch.StartNew();
        var take = page * pageSize;
        var shards = await ActiveShardsAsync(cancellationToken);

        // A shard does not know how many newer rows the other shards have, so each must return the whole
        // prefix up to the end of the page, not just its own "page N"
        var answers = await ScatterAsync(
            shards, parallel: true, allowPartial,
            (shard, ct) => _store.GetNewestAsync(shard, take, ct),
            rows => rows.Count,
            cancellationToken);

        return new DistributedPage
        {
            Page = page,
            PageSize = pageSize,
            RowsRequestedPerShard = take,
            Shards = answers.Calls,
            Partial = answers.Calls.Any(c => !c.Available),
            Items = DistributedMerge.MergeNewest(answers.Results.Select(r => (r.Shard, r.Value)), (page - 1) * pageSize, pageSize),
            TotalMilliseconds = Elapsed(total)
        };
    }

    /// <inheritdoc/>
    public async Task<DistributedPage> GetNewestFromOneShardAsync(int shard, int pageSize, CancellationToken cancellationToken = default)
    {
        var total = Stopwatch.StartNew();
        var rows = await _store.GetNewestAsync(shard, pageSize, cancellationToken);
        return new DistributedPage
        {
            Page = 1,
            PageSize = pageSize,
            RowsRequestedPerShard = pageSize,
            Shards = new List<ShardCall> { new(shard, true, rows.Count, Elapsed(total)) },
            Items = DistributedMerge.MergeNewest(new[] { (shard, rows) }, 0, pageSize),
            TotalMilliseconds = Elapsed(total)
        };
    }

    /// <inheritdoc/>
    public async Task<DistributedJoin> GetUserTasksWithProjectsAsync(Guid userId, int pageSize, CancellationToken cancellationToken = default)
    {
        var total = Stopwatch.StartNew();
        var topology = await _store.GetTopologyAsync(cancellationToken);
        var shard = topology.CreateRouter().GetShard(userId);
        var result = new DistributedJoin { Shard = shard };

        // 1. Tasks: one shard, found by the shard key
        var step = Stopwatch.StartNew();
        var tasks = await _store.GetByKeyAsync(shard, userId, 1, pageSize, cancellationToken);
        result.Steps.Add(new JoinStep($"shard-{shard}", "SELECT … FROM tasks WHERE user_id = @user ORDER BY created_at DESC LIMIT @n", tasks.Items.Count, Elapsed(step)));
        result.Shards.Add(new ShardCall(shard, true, tasks.Items.Count, Elapsed(step)));

        // 2. Projects: another database, so the JOIN turns into a second query with the collected ids
        step.Restart();
        var projectIds = tasks.Items.Where(t => t.ProjectId.HasValue).Select(t => t.ProjectId!.Value).Distinct().ToList();
        var projects = await _store.GetProjectNamesAsync(projectIds, cancellationToken);
        result.Steps.Add(new JoinStep("main", $"SELECT id, name FROM projects WHERE id = ANY(@ids), {projectIds.Count} ids", projects.Count, Elapsed(step)));

        // 3. The user: also in the main database
        step.Restart();
        result.Username = await _store.GetUsernameAsync(userId, cancellationToken);
        result.Steps.Add(new JoinStep("main", "SELECT username FROM users WHERE id = @user", result.Username is null ? 0 : 1, Elapsed(step)));

        // 4. The JOIN itself happens here, in the memory of the service
        result.Items = tasks.Items
            .Select(t => new TaskWithProject(
                t.Id, t.Title, t.Status.ToString(), t.CreatedAt, t.ProjectId,
                t.ProjectId is { } id && projects.TryGetValue(id, out var name) ? name : null))
            .ToList();
        result.TotalMilliseconds = Elapsed(total);
        return result;
    }

    /// <inheritdoc/>
    public async Task<WorkloadResult> RunWorkloadAsync(
        WorkloadDistribution distribution, int requests, Guid? hotUserId, double hotSharePercent,
        CancellationToken cancellationToken = default)
    {
        var topology = await _store.GetTopologyAsync(cancellationToken);
        var router = topology.CreateRouter();
        var shardCount = topology.ActiveShards;

        // Users and their task counts, as they are really stored on the shards
        var tasksByUser = new Dictionary<Guid, long>();
        var keys = new long[shardCount];
        var records = new long[shardCount];
        for (var shard = 0; shard < shardCount; shard++)
        {
            var counts = await _store.CountByKeyAsync(shard, cancellationToken);
            keys[shard] = counts.Count;
            records[shard] = counts.Values.Sum();
            foreach (var (user, count) in counts)
            {
                tasksByUser[user] = count;
            }
        }

        var users = tasksByUser.Keys.OrderBy(u => u).ToArray();
        var cumulative = new double[users.Length];
        var sum = 0d;
        for (var i = 0; i < users.Length; i++)
        {
            sum += tasksByUser[users[i]];
            cumulative[i] = sum;
        }

        var hot = hotUserId ?? tasksByUser.MaxBy(t => t.Value).Key;
        var random = new Random(42);
        Guid Pick()
        {
            switch (distribution)
            {
                case WorkloadDistribution.ByTasks:
                    var index = Array.BinarySearch(cumulative, random.NextDouble() * sum);
                    return users[Math.Min(index < 0 ? ~index : index, users.Length - 1)];
                case WorkloadDistribution.HotUser when random.NextDouble() * 100 < hotSharePercent:
                    return hot;
                default:
                    return users[random.Next(users.Length)];
            }
        }

        var picks = Enumerable.Range(0, requests).Select(_ => Pick()).ToArray();
        var times = Enumerable.Range(0, shardCount).Select(_ => new List<double>()).ToArray();
        var rows = new long[shardCount];
        var sync = new object();
        using var gate = new SemaphoreSlim(16);
        var total = Stopwatch.StartNew();

        await Task.WhenAll(picks.Select(async user =>
        {
            await gate.WaitAsync(cancellationToken);
            try
            {
                var shard = router.GetShard(user);
                var watch = Stopwatch.StartNew();
                var page = await _store.GetByKeyAsync(shard, user, 1, 20, cancellationToken);
                lock (sync)
                {
                    times[shard].Add(watch.Elapsed.TotalMilliseconds);
                    rows[shard] += page.Items.Count;
                }
            }
            finally
            {
                gate.Release();
            }
        }));

        return new WorkloadResult
        {
            Distribution = distribution,
            HotUserId = distribution == WorkloadDistribution.HotUser ? hot : null,
            HotSharePercent = distribution == WorkloadDistribution.HotUser ? hotSharePercent : null,
            HotUserShard = distribution == WorkloadDistribution.HotUser ? router.GetShard(hot) : null,
            Requests = requests,
            Seconds = Math.Round(total.Elapsed.TotalSeconds, 2),
            Shards = Enumerable.Range(0, shardCount).Select(shard =>
            {
                var sorted = times[shard].OrderBy(t => t).ToList();
                return new WorkloadShard(
                    shard,
                    sorted.Count,
                    Math.Round(100.0 * sorted.Count / requests, 2),
                    Math.Round(100.0 * keys[shard] / keys.Sum(), 2),
                    Math.Round(100.0 * records[shard] / records.Sum(), 2),
                    rows[shard],
                    sorted.Count == 0 ? 0 : Math.Round(sorted.Average(), 2),
                    sorted.Count == 0 ? 0 : Math.Round(sorted[(int)Math.Min(sorted.Count - 1, Math.Ceiling(sorted.Count * 0.95) - 1)], 2));
            }).ToList()
        };
    }

    /// <inheritdoc/>
    public async Task<List<ShardCall>> GetHealthAsync(CancellationToken cancellationToken = default)
    {
        var shards = await ActiveShardsAsync(cancellationToken);
        var answers = await ScatterAsync(
            shards, parallel: true, allowPartial: true,
            async (shard, ct) => { await _store.PingAsync(shard, ct); return 0; },
            _ => 0,
            cancellationToken);
        return answers.Calls;
    }

    private async Task<IReadOnlyList<int>> ActiveShardsAsync(CancellationToken cancellationToken)
    {
        var topology = await _store.GetTopologyAsync(cancellationToken);
        return Enumerable.Range(0, topology.ActiveShards).ToList();
    }

    private async Task<(List<ShardCall> Calls, List<(int Shard, T Value)> Results)> ScatterAsync<T>(
        IReadOnlyList<int> shards,
        bool parallel,
        bool allowPartial,
        Func<int, CancellationToken, Task<T>> query,
        Func<T, long> rows,
        CancellationToken cancellationToken)
    {
        async Task<(ShardCall Call, T? Value)> Run(int shard)
        {
            var watch = Stopwatch.StartNew();
            try
            {
                var value = await query(shard, cancellationToken);
                return (new ShardCall(shard, true, rows(value), Elapsed(watch)), value);
            }
            catch (ShardUnavailableException ex)
            {
                return (new ShardCall(shard, false, 0, Elapsed(watch), ex.Message), default);
            }
        }

        var answers = new List<(ShardCall Call, T? Value)>();
        if (parallel)
        {
            answers.AddRange(await Task.WhenAll(shards.Select(Run)));
        }
        else
        {
            foreach (var shard in shards)
            {
                answers.Add(await Run(shard));
            }
        }

        var failed = answers.Where(a => !a.Call.Available).Select(a => a.Call.Shard).ToList();
        if (failed.Count > 0)
        {
            _logger.LogWarning("Distributed query: shards {Shards} did not answer, partial result allowed: {Allowed}", failed, allowPartial);
            if (!allowPartial)
            {
                throw new ShardUnavailableException(failed);
            }
        }

        return (
            answers.Select(a => a.Call).OrderBy(c => c.Shard).ToList(),
            answers.Where(a => a.Call.Available).Select(a => (a.Call.Shard, a.Value!)).OrderBy(r => r.Shard).ToList());
    }

    private static double Elapsed(Stopwatch watch) => Math.Round(watch.Elapsed.TotalMilliseconds, 2);
}
