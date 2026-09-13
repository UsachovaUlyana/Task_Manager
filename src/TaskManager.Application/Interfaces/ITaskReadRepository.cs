using TaskManager.Application.Common;
using TaskManager.Domain.Entities;
using TaskManager.Domain.Enums;

namespace TaskManager.Application.Interfaces;

/// <summary>
/// Task queries served by the read replica. It exposes no write methods on purpose:
/// inserts, updates and deletes go to the primary through <see cref="ITaskRepository"/>.
/// </summary>
public interface ITaskReadRepository
{
    /// <summary>
    /// Gets a page of the user's tasks.
    /// </summary>
    Task<PagedResult<TaskItem>> GetByUserIdAsync(
        Guid userId,
        TaskItemStatus? status,
        TaskPriority? priority,
        Guid? projectId,
        DateTime? dueDateFrom,
        DateTime? dueDateTo,
        int page,
        int pageSize,
        TaskSort? sort = null,
        DateTime? createdFrom = null,
        DateTime? createdTo = null,
        CancellationToken cancellationToken = default);

    /// <summary>
    /// Gets a page of all tasks.
    /// </summary>
    Task<PagedResult<TaskItem>> GetAllFilteredAsync(
        TaskItemStatus? status,
        TaskPriority? priority,
        Guid? projectId,
        DateTime? dueDateFrom,
        DateTime? dueDateTo,
        int page,
        int pageSize,
        TaskSort? sort = null,
        DateTime? createdFrom = null,
        DateTime? createdTo = null,
        CancellationToken cancellationToken = default);

    /// <summary>
    /// Gets the number of tasks grouped by status.
    /// </summary>
    Task<IReadOnlyList<TaskStatusCount>> GetStatusStatsAsync(
        Guid? userId,
        DateTime now,
        CancellationToken cancellationToken = default);
}
