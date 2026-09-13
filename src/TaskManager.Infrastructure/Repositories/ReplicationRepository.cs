using Dapper;
using Microsoft.Extensions.Logging;
using Npgsql;
using TaskManager.Application.Interfaces;
using TaskManager.Application.Replication;

namespace TaskManager.Infrastructure.Repositories;

/// <summary>
/// Reads pg_stat_replication on the primary and the recovery state on the replica (Dapper).
/// </summary>
public class ReplicationRepository : IReplicationMonitor
{
    private const string PrimarySql = @"
        SELECT pg_is_in_recovery() AS InRecovery, pg_current_wal_lsn()::text AS Lsn";

    private const string ConnectionsSql = @"
        SELECT client_addr::text AS ClientAddr,
               application_name AS ApplicationName,
               state AS State,
               sent_lsn::text AS SentLsn,
               replay_lsn::text AS ReplayLsn,
               EXTRACT(EPOCH FROM write_lag)::float8 AS WriteLagSeconds,
               EXTRACT(EPOCH FROM flush_lag)::float8 AS FlushLagSeconds,
               EXTRACT(EPOCH FROM replay_lag)::float8 AS ReplayLagSeconds,
               pg_wal_lsn_diff(pg_current_wal_lsn(), replay_lsn)::bigint AS ReplayLagBytes,
               sync_state AS SyncState
        FROM pg_stat_replication
        ORDER BY application_name";

    private const string ReplicaSql = @"
        SELECT pg_is_in_recovery() AS InRecovery,
               pg_last_wal_receive_lsn()::text AS ReceiveLsn,
               pg_last_wal_replay_lsn()::text AS ReplayLsn,
               pg_last_xact_replay_timestamp() AS LastReplayAt,
               EXTRACT(EPOCH FROM now() - pg_last_xact_replay_timestamp())::float8 AS LagSeconds";

    private readonly string _primaryConnectionString;
    private readonly string? _replicaConnectionString;
    private readonly ILogger<ReplicationRepository> _logger;

    /// <summary>
    /// Initializes a new instance of the <see cref="ReplicationRepository"/> class.
    /// </summary>
    /// <param name="primaryConnectionString">The connection string of the primary.</param>
    /// <param name="replicaConnectionString">The connection string of the replica; null when there is none.</param>
    /// <param name="logger">The logger.</param>
    public ReplicationRepository(
        string primaryConnectionString, string? replicaConnectionString, ILogger<ReplicationRepository> logger)
    {
        _primaryConnectionString = primaryConnectionString;
        _replicaConnectionString = replicaConnectionString;
        _logger = logger;
    }

    /// <inheritdoc/>
    public async Task<ReplicationStatus> GetStatusAsync(CancellationToken cancellationToken = default)
    {
        var status = new ReplicationStatus { ReplicaConfigured = !string.IsNullOrWhiteSpace(_replicaConnectionString) };

        try
        {
            await using var primary = new NpgsqlConnection(_primaryConnectionString);
            await primary.OpenAsync(cancellationToken);

            var primaryRow = await primary.QuerySingleAsync<PrimaryRow>(PrimarySql);
            status.PrimaryLsn = primaryRow.Lsn;
            status.Connections = (await primary.QueryAsync<ReplicaConnection>(ConnectionsSql)).ToList();

            if (!status.ReplicaConfigured)
            {
                return status;
            }

            await using var replica = new NpgsqlConnection(_replicaConnectionString);
            await replica.OpenAsync(cancellationToken);

            var replicaRow = await replica.QuerySingleAsync<ReplicaRow>(ReplicaSql);
            status.ReplicaInRecovery = replicaRow.InRecovery;
            status.ReplicaReceiveLsn = replicaRow.ReceiveLsn;
            status.ReplicaReplayLsn = replicaRow.ReplayLsn;
            status.LastReplayAt = replicaRow.LastReplayAt;
            status.LagSeconds = replicaRow.LagSeconds;

            // The lag in bytes is computed on the primary: it knows both positions
            if (!string.IsNullOrEmpty(replicaRow.ReplayLsn))
            {
                status.LagBytes = await primary.ExecuteScalarAsync<long>(
                    "SELECT pg_wal_lsn_diff(pg_current_wal_lsn(), @Lsn::pg_lsn)::bigint",
                    new { Lsn = replicaRow.ReplayLsn });
            }
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            status.Error = ex.Message;
            _logger.LogError(ex, "Failed to read replication status");
        }

        return status;
    }

    private sealed class PrimaryRow
    {
        public bool InRecovery { get; set; }

        public string Lsn { get; set; } = string.Empty;
    }

    private sealed class ReplicaRow
    {
        public bool InRecovery { get; set; }

        public string? ReceiveLsn { get; set; }

        public string? ReplayLsn { get; set; }

        public DateTime? LastReplayAt { get; set; }

        public double? LagSeconds { get; set; }
    }
}
