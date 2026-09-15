using Dapper;
using Microsoft.Extensions.Logging;
using Npgsql;
using TaskManager.Application.Common;
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
        await using var connection = await OpenShardAsync(shard, cancellationToken);
        var rows = await connection.QueryAsync<(Guid Key, long Count)>(new CommandDefinition(
            "SELECT user_id, count(*) FROM tasks GROUP BY user_id", cancellationToken: cancellationToken));
        return rows.ToDictionary(r => r.Key, r => r.Count);
    }

    /// <inheritdoc/>
    public async Task<PagedResult<TaskItem>> GetByKeyAsync(
        int shard, Guid userId, int page, int pageSize, CancellationToken cancellationToken = default)
    {
        await using var connection = await OpenShardAsync(shard, cancellationToken);
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
    }

    /// <inheritdoc/>
    public async Task InsertAsync(int shard, TaskItem task, CancellationToken cancellationToken = default)
    {
        await using var connection = await OpenShardAsync(shard, cancellationToken);
        await connection.ExecuteAsync(new CommandDefinition(
            $"INSERT INTO tasks ({Columns}) VALUES (@Id, @UserId, @ProjectId, @Title, @Description, @Status, @Priority, @DueDate, @CreatedAt, @UpdatedAt)",
            new
            {
                task.Id, task.UserId, task.ProjectId, task.Title, task.Description,
                Status = (int)task.Status, Priority = (int)task.Priority, task.DueDate, task.CreatedAt, task.UpdatedAt
            },
            cancellationToken: cancellationToken));
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
                await using var connection = await OpenShardAsync(shard, cancellationToken);
                if (await connection.ExecuteScalarAsync<bool>(new CommandDefinition(
                        "SELECT EXISTS (SELECT 1 FROM tasks WHERE id = @Id)", new { Id = taskId }, cancellationToken: cancellationToken)))
                {
                    found.Add(shard);
                }
            }
            catch (NpgsqlException ex)
            {
                _logger.LogDebug(ex, "Shard {Shard} is not available", shard);
            }
        }

        return found;
    }

    private async Task<NpgsqlConnection> OpenShardAsync(int shard, CancellationToken cancellationToken)
    {
        if (shard < 0 || shard >= ConfiguredShards)
        {
            throw new ArgumentOutOfRangeException(nameof(shard), $"Shard {shard} is not configured");
        }

        var connection = new NpgsqlConnection(_options.Shards[shard].ConnectionString);
        await connection.OpenAsync(cancellationToken);
        return connection;
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
