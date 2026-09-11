using TaskManager.Application.Common;
using TaskManager.Domain.Entities;
using TaskManager.Domain.Enums;

namespace TaskManager.Application.Interfaces;

/// <summary>
/// Repository interface for TaskItem entities.
/// </summary>
public interface ITaskRepository : IRepository<TaskItem>
{
    /// <summary>
    /// Gets tasks by user ID with pagination and filtering.
    /// </summary>
    /// <param name="userId">The user ID.</param>
    /// <param name="status">Optional status filter.</param>
    /// <param name="priority">Optional priority filter.</param>
    /// <param name="projectId">Optional project ID filter.</param>
    /// <param name="dueDateFrom">Optional due date from filter.</param>
    /// <param name="dueDateTo">Optional due date to filter.</param>
    /// <param name="page">The page number (1-based).</param>
    /// <param name="pageSize">The page size.</param>
    /// <param name="sort">Optional sort order; null means newest first.</param>
    /// <param name="createdFrom">Optional minimum creation date (partition key of tasks).</param>
    /// <param name="createdTo">Optional maximum creation date, inclusive.</param>
    /// <param name="cancellationToken">The cancellation token.</param>
    /// <returns>A paginated result of tasks.</returns>
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
    /// Gets all tasks with pagination and filtering.
    /// </summary>
    /// <param name="status">Optional status filter.</param>
    /// <param name="priority">Optional priority filter.</param>
    /// <param name="projectId">Optional project ID filter.</param>
    /// <param name="dueDateFrom">Optional due date from filter.</param>
    /// <param name="dueDateTo">Optional due date to filter.</param>
    /// <param name="page">The page number (1-based).</param>
    /// <param name="pageSize">The page size.</param>
    /// <param name="sort">Optional sort order; null means newest first.</param>
    /// <param name="createdFrom">Optional minimum creation date (partition key of tasks).</param>
    /// <param name="createdTo">Optional maximum creation date, inclusive.</param>
    /// <param name="cancellationToken">The cancellation token.</param>
    /// <returns>A paginated result of tasks.</returns>
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
    /// Gets a task by ID with related data (tags, project).
    /// </summary>
    /// <param name="id">The task ID.</param>
    /// <param name="cancellationToken">The cancellation token.</param>
    /// <returns>The task if found; otherwise, null.</returns>
    Task<TaskItem?> GetByIdWithDetailsAsync(Guid id, CancellationToken cancellationToken = default);

    /// <summary>
    /// Gets the number of tasks grouped by status.
    /// </summary>
    /// <param name="userId">Optional owner filter; null means all tasks.</param>
    /// <param name="now">The moment used to decide whether a task is overdue.</param>
    /// <param name="cancellationToken">The cancellation token.</param>
    /// <returns>One entry per status that has at least one task.</returns>
    Task<IReadOnlyList<TaskStatusCount>> GetStatusStatsAsync(
        Guid? userId,
        DateTime now,
        CancellationToken cancellationToken = default);
}
