using TaskManager.Application.Sharding;

namespace TaskManager.Application.Interfaces;

/// <summary>
/// Queries over sharded tasks that need more than one shard, or more than one database.
/// </summary>
public interface IDistributedTaskQueryService
{
    /// <summary>
    /// COUNT, overdue count and AVG age by status over all shards, merged in the service.
    /// </summary>
    /// <param name="parallel">Query the shards at the same time instead of one after another.</param>
    /// <param name="allowPartial">Return what the available shards have instead of failing when a shard is down.</param>
    /// <param name="cancellationToken">The cancellation token.</param>
    Task<DistributedStats> GetStatsAsync(bool parallel, bool allowPartial, CancellationToken cancellationToken = default);

    /// <summary>
    /// A page of the newest tasks over all shards: every shard returns OFFSET + LIMIT rows, the service merges them.
    /// </summary>
    Task<DistributedPage> GetNewestAsync(int page, int pageSize, bool allowPartial, CancellationToken cancellationToken = default);

    /// <summary>
    /// The newest tasks of only one shard, to show why that is not the global answer.
    /// </summary>
    Task<DistributedPage> GetNewestFromOneShardAsync(int shard, int pageSize, CancellationToken cancellationToken = default);

    /// <summary>
    /// The user's tasks from their shard joined in the service with project names from the main database.
    /// </summary>
    Task<DistributedJoin> GetUserTasksWithProjectsAsync(Guid userId, int pageSize, CancellationToken cancellationToken = default);

    /// <summary>
    /// Runs real single-shard requests (a user's first page of tasks) for users picked by the distribution
    /// and measures how requests spread over shards compared with data.
    /// </summary>
    Task<WorkloadResult> RunWorkloadAsync(
        WorkloadDistribution distribution, int requests, Guid? hotUserId, double hotSharePercent, CancellationToken cancellationToken = default);

    /// <summary>
    /// Which active shards answer and how fast.
    /// </summary>
    Task<List<ShardCall>> GetHealthAsync(CancellationToken cancellationToken = default);
}
