using System.Text.Json.Serialization;

namespace TaskManager.Application.Sharding;

/// <summary>
/// How users are picked for workload requests.
/// </summary>
[JsonConverter(typeof(JsonStringEnumConverter))]
public enum WorkloadDistribution
{
    /// <summary>Every user is equally likely: requests follow the number of users per shard.</summary>
    Uniform,

    /// <summary>A user is picked proportionally to their tasks: active users make more requests.</summary>
    ByTasks,

    /// <summary>A share of all requests goes to one popular user, the rest are uniform.</summary>
    HotUser
}

/// <summary>
/// Per-shard result of a workload run.
/// </summary>
/// <param name="Shard">The shard number.</param>
/// <param name="Requests">Requests routed to the shard.</param>
/// <param name="RequestPercent">Share of all requests, in percent.</param>
/// <param name="KeyPercent">Share of users stored on the shard, in percent.</param>
/// <param name="RecordPercent">Share of tasks stored on the shard, in percent.</param>
/// <param name="RowsRead">Rows the shard returned.</param>
/// <param name="AverageMilliseconds">Average request time.</param>
/// <param name="P95Milliseconds">95th percentile of request time.</param>
public sealed record WorkloadShard(
    int Shard, long Requests, double RequestPercent, double KeyPercent, double RecordPercent,
    long RowsRead, double AverageMilliseconds, double P95Milliseconds);

/// <summary>
/// Result of a workload run: how requests spread over shards compared with how data spreads.
/// </summary>
public class WorkloadResult
{
    /// <summary>Gets or sets the distribution of users.</summary>
    public WorkloadDistribution Distribution { get; set; }

    /// <summary>Gets or sets the popular user for <see cref="WorkloadDistribution.HotUser"/>.</summary>
    public Guid? HotUserId { get; set; }

    /// <summary>Gets or sets the share of requests of the popular user, in percent.</summary>
    public double? HotSharePercent { get; set; }

    /// <summary>Gets or sets the shard of the popular user.</summary>
    public int? HotUserShard { get; set; }

    /// <summary>Gets or sets the number of requests.</summary>
    public int Requests { get; set; }

    /// <summary>Gets or sets how long the run took, in seconds.</summary>
    public double Seconds { get; set; }

    /// <summary>Gets or sets the per-shard result.</summary>
    public List<WorkloadShard> Shards { get; set; } = new();
}
