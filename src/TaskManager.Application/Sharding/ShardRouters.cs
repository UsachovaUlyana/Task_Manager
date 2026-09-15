using System.Text.Json.Serialization;

namespace TaskManager.Application.Sharding;

/// <summary>
/// How a shard key is mapped to a shard.
/// </summary>
[JsonConverter(typeof(JsonStringEnumConverter))]
public enum ShardStrategy
{
    /// <summary>
    /// shard = hash(key) % N.
    /// </summary>
    Modulo,

    /// <summary>
    /// The first shard point clockwise from hash(key) on a hash ring.
    /// </summary>
    ConsistentHashing
}

/// <summary>
/// Decides which PostgreSQL instance stores the records of a shard key.
/// </summary>
public interface IShardRouter
{
    /// <summary>
    /// Gets the strategy of the router.
    /// </summary>
    ShardStrategy Strategy { get; }

    /// <summary>
    /// Gets the number of shards, numbered from 0.
    /// </summary>
    int ShardCount { get; }

    /// <summary>
    /// Gets the shard of the key.
    /// </summary>
    int GetShard(Guid key);
}

/// <summary>
/// shard = hash(key) % N. Simple and even, but changing N remaps most keys.
/// </summary>
public sealed class ModuloShardRouter : IShardRouter
{
    /// <summary>
    /// Initializes a new instance of the <see cref="ModuloShardRouter"/> class.
    /// </summary>
    public ModuloShardRouter(int shardCount)
    {
        ArgumentOutOfRangeException.ThrowIfLessThan(shardCount, 1);
        ShardCount = shardCount;
    }

    /// <inheritdoc/>
    public ShardStrategy Strategy => ShardStrategy.Modulo;

    /// <inheritdoc/>
    public int ShardCount { get; }

    /// <inheritdoc/>
    public int GetShard(Guid key) => (int)(ShardHash.Of(key) % (ulong)ShardCount);
}

/// <summary>
/// Consistent hashing: every shard owns <c>virtualNodes</c> points on a ring of 2^64 positions,
/// a key belongs to the first point clockwise from its hash. Adding shard N only adds its points,
/// so the only keys that move are those that now land on the new shard.
/// </summary>
public sealed class ConsistentHashRouter : IShardRouter
{
    private readonly ulong[] _points;
    private readonly int[] _owners;

    /// <summary>
    /// Initializes a new instance of the <see cref="ConsistentHashRouter"/> class.
    /// </summary>
    /// <param name="shardCount">The number of shards.</param>
    /// <param name="virtualNodes">Points per shard on the ring; more points give a more even split.</param>
    public ConsistentHashRouter(int shardCount, int virtualNodes = 100)
    {
        ArgumentOutOfRangeException.ThrowIfLessThan(shardCount, 1);
        ArgumentOutOfRangeException.ThrowIfLessThan(virtualNodes, 1);
        ShardCount = shardCount;
        VirtualNodes = virtualNodes;

        // The point of a virtual node depends only on its shard and number, not on N:
        // the ring for N + 1 shards is the ring for N shards plus the points of the new shard
        var ring = new List<(ulong Point, int Shard)>(shardCount * virtualNodes);
        for (var shard = 0; shard < shardCount; shard++)
        {
            for (var node = 0; node < virtualNodes; node++)
            {
                ring.Add((ShardHash.Of($"shard-{shard}#vnode-{node}"), shard));
            }
        }

        ring.Sort((a, b) => a.Point.CompareTo(b.Point));
        _points = ring.Select(r => r.Point).ToArray();
        _owners = ring.Select(r => r.Shard).ToArray();
    }

    /// <inheritdoc/>
    public ShardStrategy Strategy => ShardStrategy.ConsistentHashing;

    /// <inheritdoc/>
    public int ShardCount { get; }

    /// <summary>
    /// Gets the number of points each shard owns on the ring.
    /// </summary>
    public int VirtualNodes { get; }

    /// <inheritdoc/>
    public int GetShard(Guid key)
    {
        var index = Array.BinarySearch(_points, ShardHash.Of(key));
        if (index < 0)
        {
            // Not an exact hit: ~index is the first point greater than the hash
            index = ~index;
        }

        // Past the last point the ring wraps around to the first one
        return _owners[index == _points.Length ? 0 : index];
    }
}

/// <summary>
/// Creates routers from settings.
/// </summary>
public static class ShardRouterFactory
{
    /// <summary>
    /// Creates a router of the given strategy.
    /// </summary>
    public static IShardRouter Create(ShardStrategy strategy, int shardCount, int virtualNodes) => strategy switch
    {
        ShardStrategy.Modulo => new ModuloShardRouter(shardCount),
        _ => new ConsistentHashRouter(shardCount, virtualNodes)
    };
}
