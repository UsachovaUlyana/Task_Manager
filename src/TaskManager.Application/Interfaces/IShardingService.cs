using TaskManager.Application.Common;
using TaskManager.Application.DTOs.Tasks;
using TaskManager.Application.Sharding;

namespace TaskManager.Application.Interfaces;

/// <summary>
/// Sharding of tasks by user: routing, loading, simulations and real data movement.
/// </summary>
public interface IShardingService
{
    /// <summary>Gets the topology and the real number of tasks on every active shard.</summary>
    Task<ShardDistribution> GetOverviewAsync(CancellationToken cancellationToken = default);

    /// <summary>Shows where a user's tasks live now and where both strategies would put them.</summary>
    Task<ShardRoute> RouteAsync(Guid userId, CancellationToken cancellationToken = default);

    /// <summary>Reads a page of the user's tasks from the shard chosen by the router.</summary>
    Task<ShardedTasksResult> GetUserTasksAsync(Guid userId, int page, int pageSize, CancellationToken cancellationToken = default);

    /// <summary>Creates a task on the shard chosen by the router.</summary>
    Task<ShardedTaskCreated> CreateUserTaskAsync(Guid userId, CreateTaskRequest request, CancellationToken cancellationToken = default);

    /// <summary>Sets the topology and copies all tasks of the main database to the shards.</summary>
    Task<ShardOperationResult> LoadAsync(ShardStrategy strategy, int shards, int virtualNodes, CancellationToken cancellationToken = default);

    /// <summary>Distributes the loaded keys with a hypothetical router, without moving data.</summary>
    Task<ShardDistribution> SimulateDistributionAsync(ShardStrategy strategy, int shards, int virtualNodes, CancellationToken cancellationToken = default);

    /// <summary>Counts how many loaded records would change their shard when the number of shards changes.</summary>
    Task<RebalancePlan> SimulateRebalanceAsync(ShardStrategy strategy, int fromShards, int toShards, int virtualNodes, CancellationToken cancellationToken = default);

    /// <summary>Changes the number of active shards and really moves the tasks whose shard changes.</summary>
    Task<ShardOperationResult> RebalanceAsync(int targetShards, CancellationToken cancellationToken = default);
}

/// <summary>
/// Where a shard key is routed.
/// </summary>
public class ShardRoute
{
    /// <summary>Gets or sets the shard key.</summary>
    public Guid UserId { get; set; }

    /// <summary>Gets or sets the 64-bit hash of the key.</summary>
    public string Hash { get; set; } = string.Empty;

    /// <summary>Gets or sets the topology in use.</summary>
    public ShardTopology Topology { get; set; } = null!;

    /// <summary>Gets or sets the shard chosen by the current topology.</summary>
    public int Shard { get; set; }

    /// <summary>Gets or sets the shard for hash % N with N from 2 to the configured number of shards.</summary>
    public Dictionary<string, int> Modulo { get; set; } = new();

    /// <summary>Gets or sets the shard for the hash ring with N from 2 to the configured number of shards.</summary>
    public Dictionary<string, int> ConsistentHashing { get; set; } = new();
}

/// <summary>
/// A page of tasks read from one shard.
/// </summary>
public class ShardedTasksResult
{
    /// <summary>Gets or sets the shard the page was read from.</summary>
    public int Shard { get; set; }

    /// <summary>Gets or sets the tasks.</summary>
    public PagedResult<ShardedTaskDto> Tasks { get; set; } = new();
}

/// <summary>
/// A task created on a shard.
/// </summary>
public class ShardedTaskCreated
{
    /// <summary>Gets or sets the shard chosen by the router.</summary>
    public int Shard { get; set; }

    /// <summary>Gets or sets the shards that actually contain the task after the insert.</summary>
    public IReadOnlyList<int> FoundOnShards { get; set; } = Array.Empty<int>();

    /// <summary>Gets or sets the task.</summary>
    public ShardedTaskDto Task { get; set; } = null!;
}

/// <summary>
/// A task as stored on a shard.
/// </summary>
public sealed record ShardedTaskDto(
    Guid Id, Guid UserId, Guid? ProjectId, string Title, string Status, string Priority, DateTime? DueDate, DateTime CreatedAt);
