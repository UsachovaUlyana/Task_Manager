using FluentAssertions;
using TaskManager.Application.Partitioning;

namespace TaskManager.Tests.Partitioning;

/// <summary>
/// Unit tests for AlertPolicy and AlertMessages.
/// </summary>
public class AlertPolicyTests
{
    private static readonly DateTime At = new(2026, 9, 12, 8, 0, 0, DateTimeKind.Utc);

    [Fact]
    public void Decide_ShouldSendCritical_WhenProblemIsNew()
    {
        AlertPolicy.Decide(null, PartitionStatus.Critical, "events_2026_09_14")
            .Should().Be(AlertAction.SendCritical);
        AlertPolicy.Decide(State(PartitionStatus.Ok, "", At), PartitionStatus.Critical, "events_2026_09_14")
            .Should().Be(AlertAction.SendCritical);
    }

    [Fact]
    public void Decide_ShouldNotRepeatDeliveredCritical()
    {
        var previous = State(PartitionStatus.Critical, "events_2026_09_14", At);

        AlertPolicy.Decide(previous, PartitionStatus.Critical, "events_2026_09_14").Should().Be(AlertAction.None);
    }

    [Fact]
    public void Decide_ShouldSendCritical_WhenAnotherPartitionGoesMissing()
    {
        var previous = State(PartitionStatus.Critical, "events_2026_09_14", At);

        AlertPolicy.Decide(previous, PartitionStatus.Critical, "events_2026_09_13, events_2026_09_14")
            .Should().Be(AlertAction.SendCritical);
    }

    [Fact]
    public void Decide_ShouldRetryCritical_WhenPreviousWasNotDelivered()
    {
        var previous = State(PartitionStatus.Critical, "events_2026_09_14", null);

        AlertPolicy.Decide(previous, PartitionStatus.Critical, "events_2026_09_14").Should().Be(AlertAction.SendCritical);
    }

    [Fact]
    public void Decide_ShouldSendRecovery_OnlyAfterDeliveredCritical()
    {
        AlertPolicy.Decide(State(PartitionStatus.Critical, "events_2026_09_14", At), PartitionStatus.Ok, "")
            .Should().Be(AlertAction.SendRecovery);
        AlertPolicy.Decide(State(PartitionStatus.Critical, "events_2026_09_14", null), PartitionStatus.Ok, "")
            .Should().Be(AlertAction.None);
        AlertPolicy.Decide(State(PartitionStatus.Ok, "", At), PartitionStatus.Ok, "").Should().Be(AlertAction.None);
        AlertPolicy.Decide(null, PartitionStatus.Ok, "").Should().Be(AlertAction.None);
    }

    [Fact]
    public void Messages_ShouldContainTableMissingPartitionsHorizonAndTime()
    {
        var critical = AlertMessages.Critical("lab03.events", new[] { "events_2026_09_14" }, "3 days", At);
        var recovery = AlertMessages.Recovery("lab03.events", At);

        critical.Should().Contain("Table: lab03.events").And.Contain("events_2026_09_14")
            .And.Contain("Expected horizon: 3 days").And.Contain("2026-09-12 08:00:00 UTC");
        recovery.Should().Contain("Partition check OK").And.Contain("All required partitions exist");
    }

    private static PartitionAlertState State(PartitionStatus status, string missing, DateTime? notifiedAt) =>
        new("lab03.events", status, missing, At, notifiedAt);
}
