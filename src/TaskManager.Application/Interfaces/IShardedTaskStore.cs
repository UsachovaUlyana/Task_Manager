using TaskManager.Application.Common;
using TaskManager.Application.Sharding;
using TaskManager.Domain.Entities;

namespace TaskManager.Application.Interfaces;

/// <summary>
/// Tasks stored on shards: independent PostgreSQL instances addressed by shard number.
/// </summary>
public interface IShardedTaskStore
{
    /// <summary>
    /// Gets the number of shard instances in the configuration.
    /// </summary>
    int ConfiguredShards { get; }

    /// <summary>
    /// Gets the topology stored in the main database.
    /// </summary>
    Task<ShardTopology> GetTopologyAsync(CancellationToken cancellationToken = default);

    /// <summary>
    /// Saves the topology to the main database.
    /// </summary>
    Task SaveTopologyAsync(ShardTopology topology, CancellationToken cancellationToken = default);

    /// <summary>
    /// Gets the number of tasks of every user on the given shard.
    /// </summary>
    Task<IReadOnlyDictionary<Guid, long>> CountByKeyAsync(int shard, CancellationToken cancellationToken = default);

    /// <summary>
    /// Deletes all tasks on the shards and copies every task of the main database to the shard chosen by the router.
    /// </summary>
    Task<long> LoadFromMainDatabaseAsync(IShardRouter router, CancellationToken cancellationToken = default);

    /// <summary>
    /// Moves all tasks of the users from one shard to another: copy first, then delete from the source.
    /// Safe to repeat after a failure, because already copied rows are skipped.
    /// </summary>
    Task<long> MoveKeysAsync(int fromShard, int toShard, IReadOnlyCollection<Guid> keys, CancellationToken cancellationToken = default);

    /// <summary>
    /// Gets a page of the user's tasks from the shard.
    /// </summary>
    Task<PagedResult<TaskItem>> GetByKeyAsync(int shard, Guid userId, int page, int pageSize, CancellationToken cancellationToken = default);

    /// <summary>
    /// Inserts a task into the shard.
    /// </summary>
    Task InsertAsync(int shard, TaskItem task, CancellationToken cancellationToken = default);

    /// <summary>
    /// Checks which shards contain the task: used to prove where a record landed.
    /// </summary>
    Task<IReadOnlyList<int>> FindTaskAsync(Guid taskId, CancellationToken cancellationToken = default);
}
