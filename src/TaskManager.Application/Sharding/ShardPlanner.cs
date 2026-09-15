namespace TaskManager.Application.Sharding;

/// <summary>
/// Pure calculations over shard keys and their record counts: distribution and data movement.
/// </summary>
public static class ShardPlanner
{
    /// <summary>
    /// Distributes keys over shards with the router and measures how even the result is.
    /// </summary>
    /// <param name="recordsByKey">Records per shard key.</param>
    /// <param name="router">The router.</param>
    public static ShardDistribution Distribute(IReadOnlyDictionary<Guid, long> recordsByKey, IShardRouter router)
    {
        var keys = new long[router.ShardCount];
        var records = new long[router.ShardCount];
        foreach (var (key, count) in recordsByKey)
        {
            var shard = router.GetShard(key);
            keys[shard]++;
            records[shard] += count;
        }

        return Describe(router, keys, records);
    }

    /// <summary>
    /// Compares the shard of every key before and after the change of routers.
    /// </summary>
    /// <param name="recordsByKey">Records per shard key.</param>
    /// <param name="before">The router before the change.</param>
    /// <param name="after">The router after the change.</param>
    public static RebalancePlan Plan(
        IReadOnlyDictionary<Guid, long> recordsByKey, IShardRouter before, IShardRouter after)
    {
        var plan = new RebalancePlan
        {
            Strategy = after.Strategy,
            VirtualNodes = (after as ConsistentHashRouter)?.VirtualNodes,
            FromShards = before.ShardCount,
            ToShards = after.ShardCount
        };

        var moves = new SortedDictionary<(int From, int To), long>();
        foreach (var (key, count) in recordsByKey)
        {
            plan.TotalKeys++;
            plan.TotalRecords += count;

            var from = before.GetShard(key);
            var to = after.GetShard(key);
            if (from == to)
            {
                continue;
            }

            plan.MovedKeys++;
            plan.MovedRecords += count;
            moves[(from, to)] = moves.GetValueOrDefault((from, to)) + count;
        }

        plan.MovedPercent = plan.TotalRecords == 0 ? 0 : Math.Round(100.0 * plan.MovedRecords / plan.TotalRecords, 2);
        plan.Moves = moves.ToDictionary(m => $"{m.Key.From} → {m.Key.To}", m => m.Value);
        plan.After = Distribute(recordsByKey, after);
        return plan;
    }

    /// <summary>
    /// Builds the distribution summary from per-shard counters.
    /// </summary>
    public static ShardDistribution Describe(IShardRouter router, IReadOnlyList<long> keys, IReadOnlyList<long> records)
    {
        var total = records.Sum();
        var average = (double)total / records.Count;
        var deviation = Math.Sqrt(records.Sum(r => Math.Pow(r - average, 2)) / records.Count);

        return new ShardDistribution
        {
            Strategy = router.Strategy,
            ShardCount = router.ShardCount,
            VirtualNodes = (router as ConsistentHashRouter)?.VirtualNodes,
            Shards = records
                .Select((r, i) => new ShardLoad(i, keys[i], r, total == 0 ? 0 : Math.Round(100.0 * r / total, 2)))
                .ToList(),
            MaxToAverage = total == 0 ? 0 : Math.Round(records.Max() / average, 3),
            DeviationPercent = total == 0 ? 0 : Math.Round(100 * deviation / average, 2)
        };
    }
}
