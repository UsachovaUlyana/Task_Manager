using Microsoft.EntityFrameworkCore;

namespace TaskManager.Infrastructure.Data;

/// <summary>
/// Database context bound to the read replica. The model is the same as in <see cref="AppDbContext"/>:
/// only the connection differs, and queries are not tracked because nothing here is ever saved.
/// </summary>
public class ReplicaDbContext : AppDbContext
{
    /// <summary>
    /// Initializes a new instance of the <see cref="ReplicaDbContext"/> class.
    /// </summary>
    /// <param name="options">The context options pointing to the replica.</param>
    public ReplicaDbContext(DbContextOptions<ReplicaDbContext> options) : base(options)
    {
    }
}
