using System.Diagnostics;
using Microsoft.Extensions.Logging;
using TaskManager.Application.Common;
using TaskManager.Application.DTOs.Tasks;
using TaskManager.Application.Exceptions;
using TaskManager.Application.Interfaces;
using TaskManager.Application.Sharding;
using TaskManager.Domain.Entities;
using TaskManager.Domain.Enums;

namespace TaskManager.Application.Services;

/// <summary>
/// Sharding of tasks with user_id as the shard key.
/// </summary>
public class ShardingService : IShardingService
{
    private readonly IShardedTaskStore _store;
    private readonly ILogger<ShardingService> _logger;

    /// <summary>
    /// Initializes a new instance of the <see cref="ShardingService"/> class.
    /// </summary>
    public ShardingService(IShardedTaskStore store, ILogger<ShardingService> logger)
    {
        _store = store;
        _logger = logger;
    }

    /// <inheritdoc/>
    public async Task<ShardDistribution> GetOverviewAsync(CancellationToken cancellationToken = default)
    {
        var topology = await _store.GetTopologyAsync(cancellationToken);
        var router = topology.CreateRouter();
        var keys = new long[topology.ActiveShards];
        var records = new long[topology.ActiveShards];

        // Real counts from every shard, not a calculation
        for (var shard = 0; shard < topology.ActiveShards; shard++)
        {
            var counts = await _store.CountByKeyAsync(shard, cancellationToken);
            keys[shard] = counts.Count;
            records[shard] = counts.Values.Sum();
        }

        return ShardPlanner.Describe(router, keys, records);
    }

    /// <inheritdoc/>
    public async Task<ShardRoute> RouteAsync(Guid userId, CancellationToken cancellationToken = default)
    {
        var topology = await _store.GetTopologyAsync(cancellationToken);
        var route = new ShardRoute
        {
            UserId = userId,
            Hash = ShardHash.Of(userId).ToString(),
            Topology = topology,
            Shard = topology.CreateRouter().GetShard(userId)
        };

        for (var n = 2; n <= Math.Max(_store.ConfiguredShards, 2); n++)
        {
            route.Modulo[$"N={n}"] = new ModuloShardRouter(n).GetShard(userId);
            route.ConsistentHashing[$"N={n}"] = new ConsistentHashRouter(n, topology.VirtualNodes).GetShard(userId);
        }

        return route;
    }

    /// <inheritdoc/>
    public async Task<ShardedTasksResult> GetUserTasksAsync(
        Guid userId, int page, int pageSize, CancellationToken cancellationToken = default)
    {
        var shard = (await _store.GetTopologyAsync(cancellationToken)).CreateRouter().GetShard(userId);
        var tasks = await _store.GetByKeyAsync(shard, userId, page, pageSize, cancellationToken);

        return new ShardedTasksResult
        {
            Shard = shard,
            Tasks = new PagedResult<ShardedTaskDto>
            {
                Items = tasks.Items.Select(ToDto).ToList(),
                TotalCount = tasks.TotalCount,
                Page = tasks.Page,
                PageSize = tasks.PageSize
            }
        };
    }

    /// <inheritdoc/>
    public async Task<ShardedTaskCreated> CreateUserTaskAsync(
        Guid userId, CreateTaskRequest request, CancellationToken cancellationToken = default)
    {
        var shard = (await _store.GetTopologyAsync(cancellationToken)).CreateRouter().GetShard(userId);
        var now = DateTime.UtcNow;
        var task = new TaskItem
        {
            Id = Guid.NewGuid(),
            UserId = userId,
            ProjectId = request.ProjectId,
            Title = request.Title,
            Description = request.Description,
            Status = Enum.TryParse<TaskItemStatus>(request.Status, true, out var status) ? status : TaskItemStatus.Pending,
            Priority = Enum.TryParse<TaskPriority>(request.Priority, true, out var priority) ? priority : TaskPriority.Medium,
            DueDate = request.DueDate,
            CreatedAt = now,
            UpdatedAt = now
        };

        await _store.InsertAsync(shard, task, cancellationToken);
        _logger.LogInformation("Task {TaskId} of user {UserId} written to shard {Shard}", task.Id, userId, shard);

        return new ShardedTaskCreated
        {
            Shard = shard,
            FoundOnShards = await _store.FindTaskAsync(task.Id, cancellationToken),
            Task = ToDto(task)
        };
    }

    /// <inheritdoc/>
    public async Task<ShardOperationResult> LoadAsync(
        ShardStrategy strategy, int shards, int virtualNodes, CancellationToken cancellationToken = default)
    {
        ValidateShards(shards, _store.ConfiguredShards);
        var stopwatch = Stopwatch.StartNew();
        var topology = new ShardTopology(strategy, shards, virtualNodes, DateTime.UtcNow);

        var loaded = await _store.LoadFromMainDatabaseAsync(topology.CreateRouter(), cancellationToken);
        await _store.SaveTopologyAsync(topology, cancellationToken);

        return await ResultAsync(topology, loaded, 0, stopwatch, cancellationToken);
    }

    /// <inheritdoc/>
    public async Task<ShardDistribution> SimulateDistributionAsync(
        ShardStrategy strategy, int shards, int virtualNodes, CancellationToken cancellationToken = default)
    {
        ValidateShards(shards, 64);
        var (counts, _) = await GatherAsync(cancellationToken);
        return ShardPlanner.Distribute(counts, ShardRouterFactory.Create(strategy, shards, virtualNodes));
    }

    /// <inheritdoc/>
    public async Task<RebalancePlan> SimulateRebalanceAsync(
        ShardStrategy strategy, int fromShards, int toShards, int virtualNodes, CancellationToken cancellationToken = default)
    {
        ValidateShards(fromShards, 64);
        ValidateShards(toShards, 64);
        var (counts, _) = await GatherAsync(cancellationToken);
        return ShardPlanner.Plan(
            counts,
            ShardRouterFactory.Create(strategy, fromShards, virtualNodes),
            ShardRouterFactory.Create(strategy, toShards, virtualNodes));
    }

    /// <inheritdoc/>
    public async Task<ShardOperationResult> RebalanceAsync(int targetShards, CancellationToken cancellationToken = default)
    {
        ValidateShards(targetShards, _store.ConfiguredShards);
        var stopwatch = Stopwatch.StartNew();
        var current = await _store.GetTopologyAsync(cancellationToken);
        var target = current with { ActiveShards = targetShards, UpdatedAt = DateTime.UtcNow };
        var router = target.CreateRouter();

        // Where each key really is now (not where a router says it should be) and where it must be
        var (counts, location) = await GatherAsync(cancellationToken);
        var moves = location
            .Select(l => (Key: l.Key, From: l.Value, To: router.GetShard(l.Key)))
            .Where(m => m.From != m.To)
            .GroupBy(m => (m.From, m.To))
            .ToList();

        long movedRecords = 0;
        foreach (var group in moves)
        {
            var keys = group.Select(m => m.Key).ToList();
            var moved = await _store.MoveKeysAsync(group.Key.From, group.Key.To, keys, cancellationToken);
            movedRecords += moved;
            _logger.LogInformation("Moved {Keys} users ({Records} tasks) from shard {From} to shard {To}",
                keys.Count, moved, group.Key.From, group.Key.To);
        }

        // The router switches only after the data is in place
        await _store.SaveTopologyAsync(target, cancellationToken);
        return await ResultAsync(target, movedRecords, moves.Sum(g => g.Count()), stopwatch, cancellationToken);
    }

    private async Task<(Dictionary<Guid, long> Counts, Dictionary<Guid, int> Location)> GatherAsync(
        CancellationToken cancellationToken)
    {
        var topology = await _store.GetTopologyAsync(cancellationToken);
        var counts = new Dictionary<Guid, long>();
        var location = new Dictionary<Guid, int>();
        for (var shard = 0; shard < topology.ActiveShards; shard++)
        {
            foreach (var (key, count) in await _store.CountByKeyAsync(shard, cancellationToken))
            {
                counts[key] = counts.GetValueOrDefault(key) + count;
                location[key] = shard;
            }
        }

        if (counts.Count == 0)
        {
            throw new ValidationException(new Dictionary<string, string[]>
            {
                ["shards"] = new[] { "The shards are empty: load the tasks first (POST /api/shards/load)." }
            });
        }

        return (counts, location);
    }

    private async Task<ShardOperationResult> ResultAsync(
        ShardTopology topology, long records, long keys, Stopwatch stopwatch, CancellationToken cancellationToken)
    {
        var result = new ShardOperationResult
        {
            Topology = topology,
            Records = records,
            Keys = keys,
            Seconds = Math.Round(stopwatch.Elapsed.TotalSeconds, 2)
        };

        var total = 0L;
        for (var shard = 0; shard < topology.ActiveShards; shard++)
        {
            var counts = await _store.CountByKeyAsync(shard, cancellationToken);
            var shardRecords = counts.Values.Sum();
            total += shardRecords;
            result.Shards.Add(new ShardLoad(shard, counts.Count, shardRecords, 0));
        }

        result.Shards = result.Shards
            .Select(s => s with { Percent = total == 0 ? 0 : Math.Round(100.0 * s.Records / total, 2) })
            .ToList();
        return result;
    }

    private static void ValidateShards(int shards, int max)
    {
        if (shards < 1 || shards > max)
        {
            throw new ValidationException(new Dictionary<string, string[]>
            {
                ["shards"] = new[] { $"The number of shards must be from 1 to {max}." }
            });
        }
    }

    private static ShardedTaskDto ToDto(TaskItem task) => new(
        task.Id, task.UserId, task.ProjectId, task.Title, task.Status.ToString(), task.Priority.ToString(),
        task.DueDate, task.CreatedAt);
}
