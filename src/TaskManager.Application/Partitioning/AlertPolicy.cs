using System.Globalization;

namespace TaskManager.Application.Partitioning;

/// <summary>
/// What the partition check should send.
/// </summary>
public enum AlertAction
{
    /// <summary>
    /// Nothing: the state did not change or was already reported.
    /// </summary>
    None,

    /// <summary>
    /// Report missing partitions.
    /// </summary>
    SendCritical,

    /// <summary>
    /// Report that a previously reported problem is gone.
    /// </summary>
    SendRecovery
}

/// <summary>
/// Decides when to alert so the same problem is reported once, not on every check:
/// 08:00 CRITICAL → alert, 08:05 CRITICAL → nothing, 08:15 OK → recovery.
/// </summary>
public static class AlertPolicy
{
    /// <summary>
    /// Decides what to send for the current check result.
    /// </summary>
    /// <param name="previous">The state saved by the previous check, if any.</param>
    /// <param name="status">The status found now.</param>
    /// <param name="missingPartitions">The missing partitions found now, comma-separated.</param>
    public static AlertAction Decide(PartitionAlertState? previous, PartitionStatus status, string missingPartitions)
    {
        if (status == PartitionStatus.Critical)
        {
            // The same set of missing partitions that was already delivered is not reported again;
            // a new missing partition or an undelivered alert is.
            var alreadyReported = previous is { Status: PartitionStatus.Critical, NotifiedAt: not null }
                                  && previous.MissingPartitions == missingPartitions;
            return alreadyReported ? AlertAction.None : AlertAction.SendCritical;
        }

        // Recovery only makes sense after a CRITICAL alert that actually reached someone
        return status == PartitionStatus.Ok && previous is { Status: PartitionStatus.Critical, NotifiedAt: not null }
            ? AlertAction.SendRecovery
            : AlertAction.None;
    }
}

/// <summary>
/// Texts of partition alerts.
/// </summary>
public static class AlertMessages
{
    /// <summary>
    /// Builds the alert about missing partitions.
    /// </summary>
    public static string Critical(string table, IEnumerable<string> missing, string horizon, DateTime checkedAt) =>
        $"🚨 Partition alert\n\nTable: {table}\n\nMissing partitions:\n{string.Join('\n', missing)}\n\n" +
        $"Expected horizon: {horizon}\n\nChecked at:\n{Format(checkedAt)}";

    /// <summary>
    /// Builds the recovery message.
    /// </summary>
    public static string Recovery(string table, DateTime checkedAt) =>
        $"🟢 Partition check OK\n\nTable: {table}\n\nAll required partitions exist.\n\nChecked at:\n{Format(checkedAt)}";

    private static string Format(DateTime moment) =>
        moment.ToString("yyyy-MM-dd HH:mm:ss", CultureInfo.InvariantCulture) + " UTC";
}
