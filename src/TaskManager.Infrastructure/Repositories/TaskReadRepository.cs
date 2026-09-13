using TaskManager.Application.Interfaces;
using TaskManager.Infrastructure.Data;

namespace TaskManager.Infrastructure.Repositories;

/// <summary>
/// The task queries of <see cref="TaskRepository"/> executed on the read replica:
/// the same SQL, but through <see cref="ReplicaDbContext"/>.
/// </summary>
public class TaskReadRepository : TaskRepository, ITaskReadRepository
{
    /// <summary>
    /// Initializes a new instance of the <see cref="TaskReadRepository"/> class.
    /// </summary>
    /// <param name="context">The replica database context.</param>
    public TaskReadRepository(ReplicaDbContext context) : base(context)
    {
    }
}
