using Dapper;
using Microsoft.Extensions.Logging;
using Npgsql;
using TaskManager.Application.Common;
using TaskManager.Application.Exceptions;
using TaskManager.Application.Interfaces;
using TaskManager.Application.Sharding;
using TaskManager.Domain.Entities;
using TaskManager.Domain.Enums;

namespace TaskManager.Infrastructure.Repositories;

/// <summary>
/// Tasks on shard instances (Dapper and Npgsql). The topology lives in the main database.
/// </summary>
public partial class ShardedTaskStore : IShardedTaskStore
{
    private const string Columns =
        "id, user_id, project_id, title, description, status, priority, due_date, created_at, updated_at";

    private readonly ShardingOptions _options;
    private readonly string _mainConnectionString;
    private readonly ILogger<ShardedTaskStore> _logger;

    /// <summary>
    /// Initializes a new instance of the <see cref="ShardedTaskStore"/> class.
    /// </summary>
    /// <param name="options">The shard instances.</param>
    /// <param name="mainConnectionString">The connection string of the main database (topology, source tasks).</param>
    /// <param name="logger">The logger.</param>
    public ShardedTaskStore(ShardingOptions options, string mainConnectionString, ILogger<ShardedTaskStore> logger)
    {
        _options = options;
        _mainConnectionString = mainConnectionString;
        _logger = logger;
    }

    /// <inheritdoc/>
    public int ConfiguredShards => _options.Shards.Count;

    /// <inheritdoc/>
    public async Task<ShardTopology> GetTopologyAsync(CancellationToken cancellationToken = default)
    {
        await using var connection = new NpgsqlConnection(_mainConnectionString);
        var row = await connection.QuerySingleAsync<TopologyRow>(new CommandDefinition(
            "SELECT strategy AS Strategy, active_shards AS ActiveShards, virtual_nodes AS VirtualNodes, updated_at AS UpdatedAt " +
            "FROM shard_topology WHERE id = 1", cancellationToken: cancellationToken));
        return new ShardTopology(Enum.Parse<ShardStrategy>(row.Strategy), row.ActiveShards, row.VirtualNodes, row.UpdatedAt);
    }

    /// <inheritdoc/>
    public async Task SaveTopologyAsync(ShardTopology topology, CancellationToken cancellationToken = default)
    {
        await using var connection = new NpgsqlConnection(_mainConnectionString);
        await connection.ExecuteAsync(new CommandDefinition(
            "UPDATE shard_topology SET strategy = @Strategy, active_shards = @ActiveShards, virtual_nodes = @VirtualNodes, updated_at = now() WHERE id = 1",
            new { Strategy = topology.Strategy.ToString(), topology.ActiveShards, topology.VirtualNodes },
            cancellationToken: cancellationToken));
    }

    /// <inheritdoc/>
    public async Task<IReadOnlyDictionary<Guid, long>> CountByKeyAsync(int shard, CancellationToken cancellationToken = default)
    {
        return await OnShardAsync(shard, async connection =>
        {
            var rows = await connection.QueryAsync<(Guid Key, long Count)>(new CommandDefinition(
                "SELECT user_id, count(*) FROM tasks GROUP BY user_id", cancellationToken: cancellationToken));
            return rows.ToDictionary(r => r.Key, r => r.Count);
        }, cancellationToken);
    }

    /// <inheritdoc/>
    public async Task<PagedResult<TaskItem>> GetByKeyAsync(
        int shard, Guid userId, int page, int pageSize, CancellationToken cancellationToken = default)
    {
        return await OnShardAsync(shard, async connection =>
        {
            var total = await connection.ExecuteScalarAsync<int>(new CommandDefinition(
                "SELECT count(*) FROM tasks WHERE user_id = @UserId", new { UserId = userId }, cancellationToken: cancellationToken));
            var rows = await connection.QueryAsync<TaskRow>(new CommandDefinition(
                $"SELECT {Columns} FROM tasks WHERE user_id = @UserId ORDER BY created_at DESC LIMIT @Take OFFSET @Skip",
                new { UserId = userId, Take = pageSize, Skip = (page - 1) * pageSize }, cancellationToken: cancellationToken));

            return new PagedResult<TaskItem>
            {
                Items = rows.Select(r => r.ToEntity()).ToList(),
                TotalCount = total,
                Page = page,
                PageSize = pageSize
            };
        }, cancellationToken);
    }

    /// <inheritdoc/>
    public async Task InsertAsync(int shard, TaskItem task, CancellationToken cancellationToken = default)
    {
        await OnShardAsync(shard, async connection =>
        {
            await connection.ExecuteAsync(new CommandDefinition(
                $"INSERT INTO tasks ({Columns}) VALUES (@Id, @UserId, @ProjectId, @Title, @Description, @Status, @Priority, @DueDate, @CreatedAt, @UpdatedAt)",
                new
                {
                    task.Id, task.UserId, task.ProjectId, task.Title, task.Description,
                    Status = (int)task.Status, Priority = (int)task.Priority, task.DueDate, task.CreatedAt, task.UpdatedAt
                },
                cancellationToken: cancellationToken));
        }, cancellationToken);
    }

    /// <inheritdoc/>
    public async Task<IReadOnlyList<int>> FindTaskAsync(Guid taskId, CancellationToken cancellationToken = default)
    {
        // Without the shard key the router cannot help: every shard has to be asked
        var found = new List<int>();
        for (var shard = 0; shard < ConfiguredShards; shard++)
        {
            try
            {
                var exists = await OnShardAsync(shard, connection => connection.ExecuteScalarAsync<bool>(new CommandDefinition(
                    "SELECT EXISTS (SELECT 1 FROM tasks WHERE id = @Id)", new { Id = taskId }, cancellationToken: cancellationToken)),
                    cancellationToken);
                if (exists)
                {
                    found.Add(shard);
                }
            }
            catch (ShardUnavailableException ex)
            {
                _logger.LogDebug(ex, "Shard {Shard} is not available", shard);
            }
        }

        return found;
    }

    /// <summary>
    /// Runs work on a shard connection. A lost connection — the server is down, restarting or the pooled
    /// connection was cut — means the shard is unavailable, not that the query is wrong.
    /// </summary>
    private async Task<T> OnShardAsync<T>(int shard, Func<NpgsqlConnection, Task<T>> work, CancellationToken cancellationToken)
    {
        await using var connection = await OpenShardAsync(shard, cancellationToken);
        try
        {
            return await work(connection);
        }
        catch (Exception ex) when (IsConnectionFailure(ex))
        {
            // Other pooled connections to this server are dead too
            NpgsqlConnection.ClearPool(connection);
            _logger.LogWarning("Shard {Shard} connection lost: {Reason}", shard, ex.Message);
            throw new ShardUnavailableException(new[] { shard }, ex.Message);
        }
    }

    private Task OnShardAsync(int shard, Func<NpgsqlConnection, Task> work, CancellationToken cancellationToken)
        => OnShardAsync(shard, async connection => { await work(connection); return true; }, cancellationToken);

    private static bool IsConnectionFailure(Exception ex) => ex switch
    {
        // 57P01 admin shutdown, 57P02 crash shutdown, 57P03 cannot connect now: the server is going away
        PostgresException postgres => postgres.SqlState is "57P01" or "57P02" or "57P03",
        // Any other driver error without a server response is a broken connection or a timeout
        NpgsqlException => true,
        System.Net.Sockets.SocketException or IOException or TimeoutException => true,
        _ => false
    };

    private async Task<NpgsqlConnection> OpenShardAsync(int shard, CancellationToken cancellationToken)
    {
        if (shard < 0 || shard >= ConfiguredShards)
        {
            throw new ArgumentOutOfRangeException(nameof(shard), $"Shard {shard} is not configured");
        }

        var connection = new NpgsqlConnection(_options.Shards[shard].ConnectionString);
        try
        {
            await connection.OpenAsync(cancellationToken);
            return connection;
        }
        catch (Exception ex) when (ex is NpgsqlException or System.Net.Sockets.SocketException or TimeoutException)
        {
            NpgsqlConnection.ClearPool(connection);
            await connection.DisposeAsync();
            _logger.LogWarning("Shard {Shard} is unavailable: {Reason}", shard, ex.Message);
            throw new ShardUnavailableException(new[] { shard }, ex.Message);
        }
    }

    private sealed class TopologyRow
    {
        public string Strategy { get; set; } = string.Empty;

        public int ActiveShards { get; set; }

        public int VirtualNodes { get; set; }

        public DateTime UpdatedAt { get; set; }
    }

    private sealed class TaskRow
    {
        public Guid Id { get; set; }
        public Guid User_Id { get; set; }
        public Guid? Project_Id { get; set; }
        public string Title { get; set; } = string.Empty;
        public string? Description { get; set; }
        public int Status { get; set; }
        public int Priority { get; set; }
        public DateTime? Due_Date { get; set; }
        public DateTime Created_At { get; set; }
        public DateTime Updated_At { get; set; }

        public TaskItem ToEntity() => new()
        {
            Id = Id, UserId = User_Id, ProjectId = Project_Id, Title = Title, Description = Description,
            Status = (TaskItemStatus)Status, Priority = (TaskPriority)Priority, DueDate = Due_Date,
            CreatedAt = Created_At, UpdatedAt = Updated_At
        };
    }
}
