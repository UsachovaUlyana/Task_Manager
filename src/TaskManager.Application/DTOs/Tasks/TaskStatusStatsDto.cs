namespace TaskManager.Application.DTOs.Tasks;

/// <summary>
/// Response DTO with the number of tasks for a single status.
/// </summary>
public class TaskStatusStatsDto
{
    /// <summary>
    /// Gets or sets the task status.
    /// </summary>
    public string Status { get; set; } = string.Empty;

    /// <summary>
    /// Gets or sets the number of tasks with this status.
    /// </summary>
    public int Count { get; set; }

    /// <summary>
    /// Gets or sets the number of unfinished tasks with this status whose due date has passed.
    /// </summary>
    public int OverdueCount { get; set; }
}
