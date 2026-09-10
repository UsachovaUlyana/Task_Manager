using TaskManager.Domain.Enums;

namespace TaskManager.Application.Common;

/// <summary>
/// Aggregated number of tasks for a single status.
/// </summary>
public class TaskStatusCount
{
    /// <summary>
    /// Gets or sets the task status.
    /// </summary>
    public TaskItemStatus Status { get; set; }

    /// <summary>
    /// Gets or sets the number of tasks with this status.
    /// </summary>
    public int Count { get; set; }

    /// <summary>
    /// Gets or sets the number of unfinished tasks with this status whose due date has passed.
    /// </summary>
    public int OverdueCount { get; set; }
}
