using Microsoft.Extensions.Logging;
using Npgsql;
using NpgsqlTypes;
using TaskManager.Application.Sharding;

namespace TaskManager.Infrastructure.Repositories;

/// <summary>
/// Bulk data movement: initial load from the main database and moving keys between shards.
/// </summary>
public partial class ShardedTaskStore
{
    private const int MoveBatchKeys = 500;

    /// <inheritdoc/>
    public async Task<long> LoadFromMainDatabaseAsync(IShardRouter router, CancellationToken cancellationToken = default)
    {
        if (router.ShardCount > ConfiguredShards)
        {
            throw new InvalidOperationException($"{router.ShardCount} shards requested, {ConfiguredShards} configured");
        }

        // Earlier loads may have used more shards: clear every shard that answers
        for (var shard = 0; shard < ConfiguredShards; shard++)
        {
            try
            {
                await using var connection = await OpenShardAsync(shard, cancellationToken);
                await using var truncate = new NpgsqlCommand("TRUNCATE tasks", connection);
                await truncate.ExecuteNonQueryAsync(cancellationToken);
            }
            catch (Exception ex) when (shard >= router.ShardCount && ex is NpgsqlException or System.Net.Sockets.SocketException)
            {
                _logger.LogInformation("Shard {Shard} is not running and is not used, skipped", shard);
            }
        }

        var targets = new NpgsqlConnection[router.ShardCount];
        var writers = new NpgsqlBinaryImporter[router.ShardCount];
        try
        {
            for (var shard = 0; shard < router.ShardCount; shard++)
            {
                targets[shard] = await OpenShardAsync(shard, cancellationToken);
                writers[shard] = await targets[shard].BeginBinaryImportAsync(
                    $"COPY tasks ({Columns}) FROM STDIN (FORMAT BINARY)", cancellationToken);
            }

            // One streaming pass over the main table; every row goes to the COPY stream of its shard
            await using var source = new NpgsqlConnection(_mainConnectionString);
            await source.OpenAsync(cancellationToken);
            await using var select = new NpgsqlCommand($"SELECT {Columns} FROM tasks", source);
            await using var reader = await select.ExecuteReaderAsync(cancellationToken);

            long loaded = 0;
            while (await reader.ReadAsync(cancellationToken))
            {
                var userId = reader.GetGuid(1);
                await CopyRowAsync(reader, writers[router.GetShard(userId)], cancellationToken);
                loaded++;
            }

            foreach (var writer in writers)
            {
                await writer.CompleteAsync(cancellationToken);
            }

            _logger.LogInformation("Loaded {Count} tasks to {Shards} shards with {Strategy}", loaded, router.ShardCount, router.Strategy);
            return loaded;
        }
        finally
        {
            foreach (var writer in writers.Where(w => w is not null))
            {
                await writer.DisposeAsync();
            }

            foreach (var target in targets.Where(t => t is not null))
            {
                await using var analyze = new NpgsqlCommand("ANALYZE tasks", target);
                await analyze.ExecuteNonQueryAsync(CancellationToken.None);
                await target.DisposeAsync();
            }
        }
    }

    /// <inheritdoc/>
    public async Task<long> MoveKeysAsync(
        int fromShard, int toShard, IReadOnlyCollection<Guid> keys, CancellationToken cancellationToken = default)
    {
        long moved = 0;
        foreach (var batch in keys.Chunk(MoveBatchKeys))
        {
            await using var source = await OpenShardAsync(fromShard, cancellationToken);
            await using var target = await OpenShardAsync(toShard, cancellationToken);

            // 1. Copy into a temporary table of the target and insert what is not there yet:
            //    if a previous attempt stopped after the copy, those rows are simply skipped
            await using (var transaction = await target.BeginTransactionAsync(cancellationToken))
            {
                await using (var create = new NpgsqlCommand(
                                 "CREATE TEMP TABLE incoming (LIKE tasks) ON COMMIT DROP", target, transaction))
                {
                    await create.ExecuteNonQueryAsync(cancellationToken);
                }

                await using (var writer = await target.BeginBinaryImportAsync(
                                 $"COPY incoming ({Columns}) FROM STDIN (FORMAT BINARY)", cancellationToken))
                {
                    await using var select = new NpgsqlCommand($"SELECT {Columns} FROM tasks WHERE user_id = ANY(@keys)", source);
                    select.Parameters.AddWithValue("keys", batch);
                    await using var reader = await select.ExecuteReaderAsync(cancellationToken);
                    while (await reader.ReadAsync(cancellationToken))
                    {
                        await CopyRowAsync(reader, writer, cancellationToken);
                    }

                    await writer.CompleteAsync(cancellationToken);
                }

                await using (var insert = new NpgsqlCommand(
                                 "INSERT INTO tasks SELECT * FROM incoming ON CONFLICT DO NOTHING", target, transaction))
                {
                    await insert.ExecuteNonQueryAsync(cancellationToken);
                }

                await transaction.CommitAsync(cancellationToken);
            }

            // 2. Rows are deleted from the source only after the copy is committed. Two databases
            //    cannot share one transaction, so a failure between the steps leaves a duplicate, never a loss
            await using var delete = new NpgsqlCommand("DELETE FROM tasks WHERE user_id = ANY(@keys)", source);
            delete.Parameters.AddWithValue("keys", batch);
            moved += await delete.ExecuteNonQueryAsync(cancellationToken);
        }

        return moved;
    }

    private static async Task CopyRowAsync(NpgsqlDataReader reader, NpgsqlBinaryImporter writer, CancellationToken cancellationToken)
    {
        await writer.StartRowAsync(cancellationToken);
        await writer.WriteAsync(reader.GetGuid(0), NpgsqlDbType.Uuid, cancellationToken);
        await writer.WriteAsync(reader.GetGuid(1), NpgsqlDbType.Uuid, cancellationToken);
        await WriteNullableAsync(writer, reader.IsDBNull(2) ? (Guid?)null : reader.GetGuid(2), NpgsqlDbType.Uuid, cancellationToken);
        await writer.WriteAsync(reader.GetString(3), NpgsqlDbType.Varchar, cancellationToken);
        await WriteNullableAsync(writer, reader.IsDBNull(4) ? null : reader.GetString(4), NpgsqlDbType.Text, cancellationToken);
        await writer.WriteAsync(reader.GetInt32(5), NpgsqlDbType.Integer, cancellationToken);
        await writer.WriteAsync(reader.GetInt32(6), NpgsqlDbType.Integer, cancellationToken);
        await WriteNullableAsync(writer, reader.IsDBNull(7) ? (DateTime?)null : reader.GetFieldValue<DateTime>(7), NpgsqlDbType.TimestampTz, cancellationToken);
        await writer.WriteAsync(reader.GetFieldValue<DateTime>(8), NpgsqlDbType.TimestampTz, cancellationToken);
        await writer.WriteAsync(reader.GetFieldValue<DateTime>(9), NpgsqlDbType.TimestampTz, cancellationToken);
    }

    private static async Task WriteNullableAsync<T>(
        NpgsqlBinaryImporter writer, T? value, NpgsqlDbType type, CancellationToken cancellationToken)
    {
        if (value is null)
        {
            await writer.WriteNullAsync(cancellationToken);
        }
        else
        {
            await writer.WriteAsync(value, type, cancellationToken);
        }
    }
}
