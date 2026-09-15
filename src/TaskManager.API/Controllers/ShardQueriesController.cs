using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using TaskManager.Application.DTOs.Common;
using TaskManager.Application.Interfaces;
using TaskManager.Application.Sharding;

namespace TaskManager.API.Controllers;

/// <summary>
/// Queries over sharded tasks that touch several shards or databases (Admin only).
/// </summary>
[ApiController]
[Route("api/shards/queries")]
[Produces("application/json")]
[Authorize(Roles = "Admin")]
public class ShardQueriesController : ControllerBase
{
    private readonly IDistributedTaskQueryService _queries;

    /// <summary>
    /// Initializes a new instance of the <see cref="ShardQueriesController"/> class.
    /// </summary>
    public ShardQueriesController(IDistributedTaskQueryService queries)
    {
        _queries = queries;
    }

    /// <summary>
    /// Task statistics by status over all shards: COUNT, overdue and average age merged in the service.
    /// </summary>
    [HttpGet("stats")]
    public async Task<ActionResult<ApiResponse<DistributedStats>>> Stats(
        [FromQuery] bool parallel = true, [FromQuery] bool allowPartial = false, CancellationToken cancellationToken = default)
        => Ok(ApiResponse<DistributedStats>.Ok(await _queries.GetStatsAsync(parallel, allowPartial, cancellationToken)));

    /// <summary>
    /// The newest tasks over all shards (ORDER BY created_at DESC LIMIT), merged in the service.
    /// </summary>
    [HttpGet("newest")]
    public async Task<ActionResult<ApiResponse<DistributedPage>>> Newest(
        [FromQuery] int page = 1, [FromQuery] int pageSize = 10, [FromQuery] bool allowPartial = false,
        CancellationToken cancellationToken = default)
        => Ok(ApiResponse<DistributedPage>.Ok(
            await _queries.GetNewestAsync(Math.Clamp(page, 1, 10_000), Math.Clamp(pageSize, 1, 100), allowPartial, cancellationToken)));

    /// <summary>
    /// The newest tasks of one shard only: not the global answer, shown for comparison.
    /// </summary>
    [HttpGet("newest/shard/{shard:int}")]
    public async Task<ActionResult<ApiResponse<DistributedPage>>> NewestFromOneShard(
        int shard, [FromQuery] int pageSize = 10, CancellationToken cancellationToken = default)
        => Ok(ApiResponse<DistributedPage>.Ok(
            await _queries.GetNewestFromOneShardAsync(shard, Math.Clamp(pageSize, 1, 100), cancellationToken)));

    /// <summary>
    /// The user's tasks from their shard joined with project names from the main database.
    /// </summary>
    [HttpGet("users/{userId:guid}/tasks-with-projects")]
    public async Task<ActionResult<ApiResponse<DistributedJoin>>> UserTasksWithProjects(
        Guid userId, [FromQuery] int pageSize = 10, CancellationToken cancellationToken = default)
        => Ok(ApiResponse<DistributedJoin>.Ok(
            await _queries.GetUserTasksWithProjectsAsync(userId, Math.Clamp(pageSize, 1, 100), cancellationToken)));

    /// <summary>
    /// Runs real single-shard requests for users picked by the distribution and shows how requests spread over shards.
    /// </summary>
    [HttpPost("workload")]
    public async Task<ActionResult<ApiResponse<WorkloadResult>>> Workload(
        [FromQuery] WorkloadDistribution distribution = WorkloadDistribution.Uniform, [FromQuery] int requests = 20_000,
        [FromQuery] Guid? hotUserId = null, [FromQuery] double hotSharePercent = 30, CancellationToken cancellationToken = default)
        => Ok(ApiResponse<WorkloadResult>.Ok(await _queries.RunWorkloadAsync(
            distribution, Math.Clamp(requests, 1, 200_000), hotUserId, Math.Clamp(hotSharePercent, 0, 100), cancellationToken)));

    /// <summary>
    /// Which active shards answer.
    /// </summary>
    [HttpGet("health")]
    public async Task<ActionResult<ApiResponse<List<ShardCall>>>> Health(CancellationToken cancellationToken)
        => Ok(ApiResponse<List<ShardCall>>.Ok(await _queries.GetHealthAsync(cancellationToken)));
}
