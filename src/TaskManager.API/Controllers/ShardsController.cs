using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using TaskManager.Application.DTOs.Common;
using TaskManager.Application.DTOs.Tasks;
using TaskManager.Application.Interfaces;
using TaskManager.Application.Sharding;

namespace TaskManager.API.Controllers;

/// <summary>
/// Tasks sharded by user_id across independent PostgreSQL instances (Admin only).
/// </summary>
[ApiController]
[Route("api/[controller]")]
[Produces("application/json")]
[Authorize(Roles = "Admin")]
public class ShardsController : ControllerBase
{
    private readonly IShardingService _sharding;

    /// <summary>
    /// Initializes a new instance of the <see cref="ShardsController"/> class.
    /// </summary>
    public ShardsController(IShardingService sharding)
    {
        _sharding = sharding;
    }

    /// <summary>
    /// Shows the topology and the real number of users and tasks on every active shard.
    /// </summary>
    [HttpGet]
    public async Task<ActionResult<ApiResponse<ShardDistribution>>> GetOverview(CancellationToken cancellationToken)
        => Ok(ApiResponse<ShardDistribution>.Ok(await _sharding.GetOverviewAsync(cancellationToken)));

    /// <summary>
    /// Shows which shard stores the user's tasks now and where hash % N and the hash ring would put them.
    /// </summary>
    [HttpGet("route/{userId:guid}")]
    public async Task<ActionResult<ApiResponse<ShardRoute>>> Route(Guid userId, CancellationToken cancellationToken)
        => Ok(ApiResponse<ShardRoute>.Ok(await _sharding.RouteAsync(userId, cancellationToken)));

    /// <summary>
    /// Reads the user's tasks from the shard chosen by the router.
    /// </summary>
    [HttpGet("users/{userId:guid}/tasks")]
    public async Task<ActionResult<ApiResponse<ShardedTasksResult>>> GetUserTasks(
        Guid userId, [FromQuery] int page = 1, [FromQuery] int pageSize = 10, CancellationToken cancellationToken = default)
        => Ok(ApiResponse<ShardedTasksResult>.Ok(
            await _sharding.GetUserTasksAsync(userId, Math.Max(page, 1), Math.Clamp(pageSize, 1, 100), cancellationToken)));

    /// <summary>
    /// Creates a task on the shard chosen by the router and shows on which shards it can be found.
    /// </summary>
    [HttpPost("users/{userId:guid}/tasks")]
    public async Task<ActionResult<ApiResponse<ShardedTaskCreated>>> CreateUserTask(
        Guid userId, [FromBody] CreateTaskRequest request, CancellationToken cancellationToken)
        => StatusCode(StatusCodes.Status201Created,
            ApiResponse<ShardedTaskCreated>.Ok(await _sharding.CreateUserTaskAsync(userId, request, cancellationToken)));

    /// <summary>
    /// Clears the shards, sets the topology and copies all tasks of the main database to the shards.
    /// </summary>
    [HttpPost("load")]
    public async Task<ActionResult<ApiResponse<ShardOperationResult>>> Load(
        [FromQuery] ShardStrategy strategy = ShardStrategy.ConsistentHashing, [FromQuery] int shards = 3,
        [FromQuery] int virtualNodes = 100, CancellationToken cancellationToken = default)
        => Ok(ApiResponse<ShardOperationResult>.Ok(await _sharding.LoadAsync(strategy, shards, virtualNodes, cancellationToken)));

    /// <summary>
    /// Distributes the loaded users with a hypothetical router, without moving data.
    /// </summary>
    [HttpGet("simulate/distribution")]
    public async Task<ActionResult<ApiResponse<ShardDistribution>>> SimulateDistribution(
        [FromQuery] ShardStrategy strategy, [FromQuery] int shards = 3, [FromQuery] int virtualNodes = 100,
        CancellationToken cancellationToken = default)
        => Ok(ApiResponse<ShardDistribution>.Ok(
            await _sharding.SimulateDistributionAsync(strategy, shards, virtualNodes, cancellationToken)));

    /// <summary>
    /// Counts how many loaded tasks would change their shard when the number of shards changes.
    /// </summary>
    [HttpGet("simulate/rebalance")]
    public async Task<ActionResult<ApiResponse<RebalancePlan>>> SimulateRebalance(
        [FromQuery] ShardStrategy strategy, [FromQuery] int from = 3, [FromQuery] int to = 4,
        [FromQuery] int virtualNodes = 100, CancellationToken cancellationToken = default)
        => Ok(ApiResponse<RebalancePlan>.Ok(
            await _sharding.SimulateRebalanceAsync(strategy, from, to, virtualNodes, cancellationToken)));

    /// <summary>
    /// Changes the number of active shards and really moves the tasks whose shard changes.
    /// </summary>
    [HttpPost("rebalance")]
    public async Task<ActionResult<ApiResponse<ShardOperationResult>>> Rebalance(
        [FromQuery] int shards, CancellationToken cancellationToken)
        => Ok(ApiResponse<ShardOperationResult>.Ok(await _sharding.RebalanceAsync(shards, cancellationToken)));
}
