namespace TaskManager.Application.Sharding;

/// <summary>
/// Shard instances ("Sharding" section). The topology — strategy and how many of these shards
/// are in use — is stored in the main database, so it survives restarts and data moves.
/// </summary>
public class ShardingOptions
{
    /// <summary>
    /// Configuration section name.
    /// </summary>
    public const string SectionName = "Sharding";

    /// <summary>
    /// Gets or sets the PostgreSQL instances that can hold shards, in shard number order.
    /// </summary>
    public List<ShardInstanceOptions> Shards { get; set; } = new();
}

/// <summary>
/// One PostgreSQL instance of the shard list.
/// </summary>
public class ShardInstanceOptions
{
    /// <summary>
    /// Gets or sets the connection string of the instance.
    /// </summary>
    public string ConnectionString { get; set; } = string.Empty;
}

/// <summary>
/// The current topology: which strategy routes keys and how many shards are in use.
/// </summary>
/// <param name="Strategy">The routing strategy.</param>
/// <param name="ActiveShards">How many shards from the list hold data.</param>
/// <param name="VirtualNodes">Points per shard on the hash ring.</param>
/// <param name="UpdatedAt">When the topology last changed (UTC).</param>
public sealed record ShardTopology(ShardStrategy Strategy, int ActiveShards, int VirtualNodes, DateTime UpdatedAt)
{
    /// <summary>
    /// Creates the router that matches the topology.
    /// </summary>
    public IShardRouter CreateRouter() => ShardRouterFactory.Create(Strategy, ActiveShards, VirtualNodes);
}

/// <summary>
/// Records on one shard.
/// </summary>
/// <param name="Shard">The shard number.</param>
/// <param name="Keys">Shard keys (users) on the shard.</param>
/// <param name="Records">Tasks on the shard.</param>
/// <param name="Percent">Share of all tasks, in percent.</param>
public sealed record ShardLoad(int Shard, long Keys, long Records, double Percent);

/// <summary>
/// Distribution of records over shards and how uneven it is.
/// </summary>
public class ShardDistribution
{
    /// <summary>Gets or sets the strategy used to place the records.</summary>
    public ShardStrategy Strategy { get; set; }

    /// <summary>Gets or sets the number of shards.</summary>
    public int ShardCount { get; set; }

    /// <summary>Gets or sets the virtual nodes per shard (hash ring only).</summary>
    public int? VirtualNodes { get; set; }

    /// <summary>Gets or sets the per-shard load.</summary>
    public List<ShardLoad> Shards { get; set; } = new();

    /// <summary>Gets or sets the largest shard divided by the average one, by records: 1.00 is a perfect split.</summary>
    public double MaxToAverage { get; set; }

    /// <summary>Gets or sets the relative standard deviation of shard sizes by records, in percent.</summary>
    public double DeviationPercent { get; set; }
}

/// <summary>
/// How many records change their shard when the number of shards changes.
/// </summary>
public class RebalancePlan
{
    /// <summary>Gets or sets the strategy.</summary>
    public ShardStrategy Strategy { get; set; }

    /// <summary>Gets or sets the virtual nodes per shard (hash ring only).</summary>
    public int? VirtualNodes { get; set; }

    /// <summary>Gets or sets the number of shards before the change.</summary>
    public int FromShards { get; set; }

    /// <summary>Gets or sets the number of shards after the change.</summary>
    public int ToShards { get; set; }

    /// <summary>Gets or sets the number of records.</summary>
    public long TotalRecords { get; set; }

    /// <summary>Gets or sets the records that change their shard.</summary>
    public long MovedRecords { get; set; }

    /// <summary>Gets or sets the moved share of records, in percent.</summary>
    public double MovedPercent { get; set; }

    /// <summary>Gets or sets the number of shard keys.</summary>
    public long TotalKeys { get; set; }

    /// <summary>Gets or sets the shard keys that change their shard.</summary>
    public long MovedKeys { get; set; }

    /// <summary>Gets or sets the flows of records between shards, e.g. "0 → 3": 25 000.</summary>
    public Dictionary<string, long> Moves { get; set; } = new();

    /// <summary>Gets or sets the distribution after the change.</summary>
    public ShardDistribution After { get; set; } = new();
}

/// <summary>
/// Result of loading tasks from the main database to the shards or of a real data move.
/// </summary>
public class ShardOperationResult
{
    /// <summary>Gets or sets the topology after the operation.</summary>
    public ShardTopology Topology { get; set; } = null!;

    /// <summary>Gets or sets the records processed: loaded or moved.</summary>
    public long Records { get; set; }

    /// <summary>Gets or sets the shard keys processed.</summary>
    public long Keys { get; set; }

    /// <summary>Gets or sets how long the operation took, in seconds.</summary>
    public double Seconds { get; set; }

    /// <summary>Gets or sets the records on each shard after the operation.</summary>
    public List<ShardLoad> Shards { get; set; } = new();
}
