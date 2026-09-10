namespace TaskManager.Application.Common;

/// <summary>
/// Field a task list can be sorted by.
/// </summary>
public enum TaskSortField
{
    /// <summary>
    /// Task creation time.
    /// </summary>
    CreatedAt,

    /// <summary>
    /// Task due date.
    /// </summary>
    DueDate,

    /// <summary>
    /// Task priority.
    /// </summary>
    Priority,

    /// <summary>
    /// Task title.
    /// </summary>
    Title
}
