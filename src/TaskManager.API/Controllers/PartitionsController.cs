using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using TaskManager.Application.DTOs.Common;
using TaskManager.Application.Interfaces;
using TaskManager.Application.Partitioning;

namespace TaskManager.API.Controllers;

/// <summary>
/// Partition maintenance: status, manual run of the job and of the health check (Admin only).
/// </summary>
[ApiController]
[Route("api/[controller]")]
[Produces("application/json")]
[Authorize(Roles = "Admin")]
public class PartitionsController : ControllerBase
{
    private readonly IPartitionMaintenanceService _service;

    /// <summary>
    /// Initializes a new instance of the <see cref="PartitionsController"/> class.
    /// </summary>
    /// <param name="service">The partition maintenance service.</param>
    public PartitionsController(IPartitionMaintenanceService service)
    {
        _service = service;
    }

    /// <summary>
    /// Shows which required partitions exist and which are missing. Does not send alerts.
    /// </summary>
    /// <param name="cancellationToken">The cancellation token.</param>
    /// <response code="200">Returns the state of each partitioned table.</response>
    [HttpGet]
    [ProducesResponseType(typeof(ApiResponse<PartitionRunResult>), StatusCodes.Status200OK)]
    public async Task<ActionResult<ApiResponse<PartitionRunResult>>> GetStatus(CancellationToken cancellationToken)
    {
        var result = await _service.CheckAsync(notify: false, cancellationToken);
        return Ok(ApiResponse<PartitionRunResult>.Ok(result));
    }

    /// <summary>
    /// Runs the partition health check now and sends an alert or a recovery message if needed.
    /// </summary>
    /// <param name="cancellationToken">The cancellation token.</param>
    /// <response code="200">Returns the check result and what was sent.</response>
    [HttpPost("check")]
    [ProducesResponseType(typeof(ApiResponse<PartitionRunResult>), StatusCodes.Status200OK)]
    public async Task<ActionResult<ApiResponse<PartitionRunResult>>> Check(CancellationToken cancellationToken)
    {
        var result = await _service.CheckAsync(notify: true, cancellationToken);
        return Ok(ApiResponse<PartitionRunResult>.Ok(result));
    }

    /// <summary>
    /// Runs the partition job now: creates missing partitions and drops expired ones.
    /// </summary>
    /// <param name="cancellationToken">The cancellation token.</param>
    /// <response code="200">Returns the created and dropped partitions.</response>
    [HttpPost("ensure")]
    [ProducesResponseType(typeof(ApiResponse<PartitionRunResult>), StatusCodes.Status200OK)]
    public async Task<ActionResult<ApiResponse<PartitionRunResult>>> Ensure(CancellationToken cancellationToken)
    {
        var result = await _service.EnsurePartitionsAsync(cancellationToken);
        return Ok(ApiResponse<PartitionRunResult>.Ok(result));
    }
}
