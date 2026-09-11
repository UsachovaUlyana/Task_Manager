using System.Globalization;
using System.Text.RegularExpressions;
using Dapper;
using Microsoft.EntityFrameworkCore;
using Npgsql;
using TaskManager.Application.Interfaces;
using TaskManager.Application.Partitioning;
using TaskManager.Infrastructure.Data;

namespace TaskManager.Infrastructure.Repositories;

/// <summary>
/// Reads and changes partitions through the PostgreSQL system catalog (Dapper).
/// </summary>
public class PartitionRepository : IPartitionRepository
{
    private const string ParentSql = @"
        SELECT n.nspname AS Schema, cl.relname AS Name, format_type(a.atttypid, a.atttypmod) AS KeyType
        FROM pg_partitioned_table pt
        JOIN pg_class cl ON cl.oid = pt.partrelid
        JOIN pg_namespace n ON n.oid = cl.relnamespace
        JOIN pg_attribute a ON a.attrelid = pt.partrelid AND a.attnum = pt.partattrs[0]
        WHERE pt.partrelid = to_regclass(@Table)";

    private readonly string _connectionString;

    /// <summary>
    /// Initializes a new instance of the <see cref="PartitionRepository"/> class.
    /// </summary>
    /// <param name="context">The database context (used for its connection string).</param>
    public PartitionRepository(AppDbContext context)
    {
        _connectionString = context.Database.GetConnectionString()
            ?? throw new InvalidOperationException("Connection string is not configured");
    }

    /// <inheritdoc/>
    public async Task<bool> IsPartitionedAsync(string table, CancellationToken cancellationToken = default)
    {
        await using var connection = await OpenAsync(cancellationToken);
        return await connection.ExecuteScalarAsync<bool>(
            "SELECT EXISTS (SELECT 1 FROM pg_partitioned_table WHERE partrelid = to_regclass(@Table))",
            new { Table = table });
    }

    /// <inheritdoc/>
    public async Task<IReadOnlyList<ExistingPartition>> GetPartitionsAsync(
        string table, CancellationToken cancellationToken = default)
    {
        await using var connection = await OpenAsync(cancellationToken);
        var rows = await connection.QueryAsync<PartitionRow>(@"
            SELECT c.relname AS Name, pg_get_expr(c.relpartbound, c.oid) AS Bound
            FROM pg_inherits i
            JOIN pg_class c ON c.oid = i.inhrelid
            WHERE i.inhparent = to_regclass(@Table)
            ORDER BY c.relname", new { Table = table });

        return rows
            .Select(r =>
            {
                var (from, to) = PartitionBoundParser.Parse(r.Bound);
                return new ExistingPartition(r.Name, from, to);
            })
            .ToList();
    }

    /// <inheritdoc/>
    public async Task CreatePartitionAsync(
        string table, PartitionRange partition, CancellationToken cancellationToken = default)
    {
        await using var connection = await OpenAsync(cancellationToken);
        var parent = await connection.QuerySingleAsync<ParentRow>(ParentSql, new { Table = table });

        var sql = $"CREATE TABLE IF NOT EXISTS {Quote(parent.Schema)}.{Quote(partition.Name)} " +
                  $"PARTITION OF {Quote(parent.Schema)}.{Quote(parent.Name)} " +
                  $"FOR VALUES FROM ({Literal(partition.From, parent.KeyType)}) TO ({Literal(partition.To, parent.KeyType)})";
        await connection.ExecuteAsync(sql);
    }

    /// <inheritdoc/>
    public async Task DropPartitionAsync(string table, string partitionName, CancellationToken cancellationToken = default)
    {
        await using var connection = await OpenAsync(cancellationToken);
        var parent = await connection.QuerySingleAsync<ParentRow>(ParentSql, new { Table = table });

        // DETACH fails for a table that is not a partition of this parent, so nothing else can be dropped
        await connection.ExecuteAsync(
            $"ALTER TABLE {Quote(parent.Schema)}.{Quote(parent.Name)} DETACH PARTITION {Quote(parent.Schema)}.{Quote(partitionName)}");
        await connection.ExecuteAsync($"DROP TABLE {Quote(parent.Schema)}.{Quote(partitionName)}");
    }

    /// <inheritdoc/>
    public async Task<PartitionAlertState?> GetAlertStateAsync(string table, CancellationToken cancellationToken = default)
    {
        await using var connection = await OpenAsync(cancellationToken);
        var row = await connection.QuerySingleOrDefaultAsync<AlertStateRow>(@"
            SELECT table_name AS TableName, status AS Status, missing_partitions AS MissingPartitions,
                   changed_at AS ChangedAt, notified_at AS NotifiedAt
            FROM partition_alert_state
            WHERE table_name = @Table", new { Table = table });

        return row is null
            ? null
            : new PartitionAlertState(row.TableName, Enum.Parse<PartitionStatus>(row.Status), row.MissingPartitions,
                row.ChangedAt, row.NotifiedAt);
    }

    /// <inheritdoc/>
    public async Task SaveAlertStateAsync(PartitionAlertState state, CancellationToken cancellationToken = default)
    {
        await using var connection = await OpenAsync(cancellationToken);
        await connection.ExecuteAsync(@"
            INSERT INTO partition_alert_state (table_name, status, missing_partitions, changed_at, notified_at)
            VALUES (@Table, @Status, @MissingPartitions, @ChangedAt, @NotifiedAt)
            ON CONFLICT (table_name) DO UPDATE
            SET status = EXCLUDED.status,
                missing_partitions = EXCLUDED.missing_partitions,
                changed_at = EXCLUDED.changed_at,
                notified_at = EXCLUDED.notified_at", new
        {
            state.Table,
            Status = state.Status.ToString(),
            state.MissingPartitions,
            ChangedAt = DateTime.SpecifyKind(state.ChangedAt, DateTimeKind.Utc),
            NotifiedAt = state.NotifiedAt.HasValue ? DateTime.SpecifyKind(state.NotifiedAt.Value, DateTimeKind.Utc) : (DateTime?)null
        });
    }

    private async Task<NpgsqlConnection> OpenAsync(CancellationToken cancellationToken)
    {
        var connection = new NpgsqlConnection(_connectionString);
        await connection.OpenAsync(cancellationToken);

        // pg_get_expr prints timestamptz bounds in the session time zone
        await connection.ExecuteAsync("SET TIME ZONE 'UTC'");
        return connection;
    }

    private static string Quote(string identifier) => "\"" + identifier.Replace("\"", "\"\"") + "\"";

    private static string Literal(DateTime value, string keyType)
    {
        var text = keyType == "date"
            ? value.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture)
            : value.ToString("yyyy-MM-dd HH:mm:ss", CultureInfo.InvariantCulture);
        return keyType == "timestamp with time zone" ? $"'{text}+00'" : $"'{text}'";
    }

    private sealed class PartitionRow
    {
        public string Name { get; set; } = string.Empty;

        public string Bound { get; set; } = string.Empty;
    }

    private sealed class ParentRow
    {
        public string Schema { get; set; } = string.Empty;

        public string Name { get; set; } = string.Empty;

        public string KeyType { get; set; } = string.Empty;
    }

    private sealed class AlertStateRow
    {
        public string TableName { get; set; } = string.Empty;

        public string Status { get; set; } = string.Empty;

        public string MissingPartitions { get; set; } = string.Empty;

        public DateTime ChangedAt { get; set; }

        public DateTime? NotifiedAt { get; set; }
    }
}

/// <summary>
/// Parses the partition bound printed by pg_get_expr, for example
/// FOR VALUES FROM ('2026-09-01 00:00:00+00') TO ('2026-10-01 00:00:00+00').
/// </summary>
public static class PartitionBoundParser
{
    private static readonly Regex RangeBound = new(@"FROM \('([^']+)'\) TO \('([^']+)'\)", RegexOptions.Compiled);
    private static readonly Regex ShortOffset = new(@"(\d{2}:\d{2}:\d{2}(?:\.\d+)?[+-]\d{2})$", RegexOptions.Compiled);

    /// <summary>
    /// Gets the UTC bounds of a range partition; null for DEFAULT, MINVALUE/MAXVALUE and non-time bounds.
    /// </summary>
    public static (DateTime? From, DateTime? To) Parse(string? bound)
    {
        var match = RangeBound.Match(bound ?? string.Empty);
        return match.Success
            ? (ParseValue(match.Groups[1].Value), ParseValue(match.Groups[2].Value))
            : (null, null);
    }

    private static DateTime? ParseValue(string value)
    {
        // timestamptz is printed with a short offset ("+00"), which .NET does not accept without minutes
        var normalized = ShortOffset.Replace(value, "$1:00");
        return DateTimeOffset.TryParse(normalized, CultureInfo.InvariantCulture, DateTimeStyles.AssumeUniversal, out var parsed)
            ? parsed.UtcDateTime
            : null;
    }
}
