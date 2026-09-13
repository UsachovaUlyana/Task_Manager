using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using TaskManager.Application.DTOs.Common;
using TaskManager.Application.Interfaces;
using TaskManager.Application.Replication;

namespace TaskManager.API.Controllers;

/// <summary>
/// State of streaming replication between the primary and the read replica (Admin only).
/// </summary>
[ApiController]
[Route("api/[controller]")]
[Produces("application/json")]
[Authorize(Roles = "Admin")]
public class ReplicationController : ControllerBase
{
    private readonly IReplicationMonitor _monitor;

    /// <summary>
    /// Initializes a new instance of the <see cref="ReplicationController"/> class.
    /// </summary>
    /// <param name="monitor">The replication monitor.</param>
    public ReplicationController(IReplicationMonitor monitor)
    {
        _monitor = monitor;
    }

    /// <summary>
    /// Shows the WAL position of the primary, the position replayed by the replica and the lag between them.
    /// </summary>
    /// <param name="cancellationToken">The cancellation token.</param>
    /// <response code="200">Returns the replication state.</response>
    [HttpGet]
    [ProducesResponseType(typeof(ApiResponse<ReplicationStatus>), StatusCodes.Status200OK)]
    public async Task<ActionResult<ApiResponse<ReplicationStatus>>> GetStatus(CancellationToken cancellationToken)
    {
        var status = await _monitor.GetStatusAsync(cancellationToken);
        return Ok(ApiResponse<ReplicationStatus>.Ok(status));
    }
}
