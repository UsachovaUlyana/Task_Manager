using Dapper;
using Npgsql;
using TaskManager.Application.Sharding;
using TaskManager.Domain.Entities;

namespace TaskManager.Infrastructure.Repositories;

/// <summary>
/// Queries that are parts of distributed requests: each runs on one shard, the service merges the results.
/// </summary>
public partial class ShardedTaskStore
{
    /// <inheritdoc/>
    public async Task<IReadOnlyList<StatusAggregate>> AggregateByStatusAsync(
        int shard, DateTime now, CancellationToken cancellationToken = default)
    {
        return await OnShardAsync(shard, async connection =>
        {
            var rows = await connection.QueryAsync<StatusAggregate>(new CommandDefinition(@"
                SELECT status AS Status,
                       count(*) AS Count,
                       count(*) FILTER (WHERE due_date < @Now AND status IN (0, 1)) AS Overdue,
                       coalesce(sum(extract(epoch FROM (@Now - created_at)) / 86400), 0)::float8 AS AgeDaysSum
                FROM tasks
                GROUP BY status
                ORDER BY status",
                new { Now = now }, cancellationToken: cancellationToken));
            return rows.ToList();
        }, cancellationToken);
    }

    /// <inheritdoc/>
    public async Task<IReadOnlyList<TaskItem>> GetNewestAsync(int shard, int take, CancellationToken cancellationToken = default)
    {
        return await OnShardAsync(shard, async connection =>
        {
            var rows = await connection.QueryAsync<TaskRow>(new CommandDefinition(
                $"SELECT {Columns} FROM tasks ORDER BY created_at DESC, id DESC LIMIT @Take",
                new { Take = take }, cancellationToken: cancellationToken));
            return rows.Select(r => r.ToEntity()).ToList();
        }, cancellationToken);
    }

    /// <inheritdoc/>
    public async Task<IReadOnlyDictionary<Guid, string>> GetProjectNamesAsync(
        IReadOnlyCollection<Guid> projectIds, CancellationToken cancellationToken = default)
    {
        if (projectIds.Count == 0)
        {
            return new Dictionary<Guid, string>();
        }

        await using var connection = new NpgsqlConnection(_mainConnectionString);
        var rows = await connection.QueryAsync<(Guid Id, string Name)>(new CommandDefinition(
            "SELECT id, name FROM projects WHERE id = ANY(@Ids)", new { Ids = projectIds.ToArray() },
            cancellationToken: cancellationToken));
        return rows.ToDictionary(r => r.Id, r => r.Name);
    }

    /// <inheritdoc/>
    public async Task<string?> GetUsernameAsync(Guid userId, CancellationToken cancellationToken = default)
    {
        await using var connection = new NpgsqlConnection(_mainConnectionString);
        return await connection.ExecuteScalarAsync<string?>(new CommandDefinition(
            "SELECT username FROM users WHERE id = @Id", new { Id = userId }, cancellationToken: cancellationToken));
    }

    /// <inheritdoc/>
    public async Task PingAsync(int shard, CancellationToken cancellationToken = default)
    {
        await OnShardAsync(shard, async connection =>
        {
            await connection.ExecuteScalarAsync<int>(new CommandDefinition("SELECT 1", cancellationToken: cancellationToken));
        }, cancellationToken);
    }
}
