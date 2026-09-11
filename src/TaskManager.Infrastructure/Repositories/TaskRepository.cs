using Microsoft.EntityFrameworkCore;
using TaskManager.Application.Common;
using TaskManager.Application.Interfaces;
using TaskManager.Domain.Entities;
using TaskManager.Domain.Enums;
using TaskManager.Infrastructure.Data;

namespace TaskManager.Infrastructure.Repositories;

/// <summary>
/// Repository implementation for TaskItem entities.
/// </summary>
public class TaskRepository : BaseRepository<TaskItem>, ITaskRepository
{
    /// <summary>
    /// Initializes a new instance of the <see cref="TaskRepository"/> class.
    /// </summary>
    /// <param name="context">The database context.</param>
    public TaskRepository(AppDbContext context) : base(context)
    {
    }

    /// <inheritdoc/>
    public async Task<PagedResult<TaskItem>> GetByUserIdAsync(
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
        CancellationToken cancellationToken = default)
    {
        var query = DbSet
            .Include(t => t.TaskTags)
            .ThenInclude(tt => tt.Tag)
            .Include(t => t.Project)
            .Where(t => t.UserId == userId)
            .AsQueryable();

        query = ApplyFilters(query, status, priority, projectId, dueDateFrom, dueDateTo, createdFrom, createdTo);

        var totalCount = await query.CountAsync(cancellationToken);

        var items = await ApplySort(query, sort ?? TaskSort.Default)
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .ToListAsync(cancellationToken);

        return new PagedResult<TaskItem>
        {
            Items = items,
            TotalCount = totalCount,
            Page = page,
            PageSize = pageSize
        };
    }

    /// <inheritdoc/>
    public async Task<PagedResult<TaskItem>> GetAllFilteredAsync(
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
        CancellationToken cancellationToken = default)
    {
        var query = DbSet
            .Include(t => t.TaskTags)
            .ThenInclude(tt => tt.Tag)
            .Include(t => t.Project)
            .Include(t => t.User)
            .AsQueryable();

        query = ApplyFilters(query, status, priority, projectId, dueDateFrom, dueDateTo, createdFrom, createdTo);

        var totalCount = await query.CountAsync(cancellationToken);

        var items = await ApplySort(query, sort ?? TaskSort.Default)
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .ToListAsync(cancellationToken);

        return new PagedResult<TaskItem>
        {
            Items = items,
            TotalCount = totalCount,
            Page = page,
            PageSize = pageSize
        };
    }

    /// <inheritdoc/>
    public async Task<TaskItem?> GetByIdWithDetailsAsync(Guid id, CancellationToken cancellationToken = default)
    {
        return await DbSet
            .Include(t => t.TaskTags)
            .ThenInclude(tt => tt.Tag)
            .Include(t => t.Project)
            .Include(t => t.User)
            .FirstOrDefaultAsync(t => t.Id == id, cancellationToken);
    }

    /// <inheritdoc/>
    public async Task<IReadOnlyList<TaskStatusCount>> GetStatusStatsAsync(
        Guid? userId,
        DateTime now,
        CancellationToken cancellationToken = default)
    {
        var query = DbSet.AsQueryable();

        if (userId.HasValue)
        {
            query = query.Where(t => t.UserId == userId.Value);
        }

        return await query
            .GroupBy(t => t.Status)
            .Select(g => new TaskStatusCount
            {
                Status = g.Key,
                Count = g.Count(),
                OverdueCount = g.Count(t => t.DueDate < now
                    && (t.Status == TaskItemStatus.Pending || t.Status == TaskItemStatus.InProgress))
            })
            .OrderBy(s => s.Status)
            .ToListAsync(cancellationToken);
    }

    private static IQueryable<TaskItem> ApplySort(IQueryable<TaskItem> query, TaskSort sort)
    {
        // created_at is effectively unique; other fields repeat a lot, so ties are broken
        // by creation time to keep pages stable. The default order matches idx_tasks_*_created_at.
        return sort.Field switch
        {
            TaskSortField.DueDate => (sort.Descending
                    ? query.OrderByDescending(t => t.DueDate)
                    : query.OrderBy(t => t.DueDate))
                .ThenByDescending(t => t.CreatedAt),
            TaskSortField.Priority => (sort.Descending
                    ? query.OrderByDescending(t => t.Priority)
                    : query.OrderBy(t => t.Priority))
                .ThenByDescending(t => t.CreatedAt),
            TaskSortField.Title => (sort.Descending
                    ? query.OrderByDescending(t => t.Title)
                    : query.OrderBy(t => t.Title))
                .ThenByDescending(t => t.CreatedAt),
            _ => sort.Descending
                ? query.OrderByDescending(t => t.CreatedAt)
                : query.OrderBy(t => t.CreatedAt)
        };
    }

    private static IQueryable<TaskItem> ApplyFilters(
        IQueryable<TaskItem> query,
        TaskItemStatus? status,
        TaskPriority? priority,
        Guid? projectId,
        DateTime? dueDateFrom,
        DateTime? dueDateTo,
        DateTime? createdFrom,
        DateTime? createdTo)
    {
        if (status.HasValue)
        {
            query = query.Where(t => t.Status == status.Value);
        }

        if (priority.HasValue)
        {
            query = query.Where(t => t.Priority == priority.Value);
        }

        if (projectId.HasValue)
        {
            query = query.Where(t => t.ProjectId == projectId.Value);
        }

        if (dueDateFrom.HasValue)
        {
            query = query.Where(t => t.DueDate >= dueDateFrom.Value);
        }

        if (dueDateTo.HasValue)
        {
            query = query.Where(t => t.DueDate <= dueDateTo.Value);
        }

        // created_at is the partition key of tasks: these conditions let PostgreSQL skip other partitions
        if (createdFrom.HasValue)
        {
            query = query.Where(t => t.CreatedAt >= createdFrom.Value);
        }

        if (createdTo.HasValue)
        {
            query = query.Where(t => t.CreatedAt <= createdTo.Value);
        }

        return query;
    }
}
