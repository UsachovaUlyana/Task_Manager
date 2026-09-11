using FluentAssertions;
using TaskManager.Application.Partitioning;

namespace TaskManager.Tests.Partitioning;

/// <summary>
/// Unit tests for PartitionPlanner.
/// </summary>
public class PartitionPlannerTests
{
    private static readonly DateTime Now = new(2026, 9, 11, 21, 30, 0, DateTimeKind.Utc);

    [Fact]
    public void RequiredPartitions_ShouldCoverCurrentDayAndThreeDaysAhead()
    {
        // Act
        var required = PartitionPlanner.RequiredPartitions("lab03.events", Now, PartitionInterval.Day, 3);

        // Assert
        required.Select(p => p.Name).Should().Equal(
            "events_2026_09_11", "events_2026_09_12", "events_2026_09_13", "events_2026_09_14");
        required[3].From.Should().Be(new DateTime(2026, 9, 14, 0, 0, 0, DateTimeKind.Utc));
        required[3].To.Should().Be(new DateTime(2026, 9, 15, 0, 0, 0, DateTimeKind.Utc));
    }

    [Fact]
    public void RequiredPartitions_ShouldCrossYearBoundaryForMonths()
    {
        // Act
        var required = PartitionPlanner.RequiredPartitions(
            "tasks", new DateTime(2026, 11, 20, 0, 0, 0, DateTimeKind.Utc), PartitionInterval.Month, 3);

        // Assert
        required.Select(p => p.Name).Should().Equal("tasks_2026_11", "tasks_2026_12", "tasks_2027_01", "tasks_2027_02");
        required[1].To.Should().Be(new DateTime(2027, 1, 1, 0, 0, 0, DateTimeKind.Utc));
    }

    [Fact]
    public void FindMissing_ShouldCompareBoundsNotNames()
    {
        // Arrange
        var required = PartitionPlanner.RequiredPartitions("lab03.events", Now, PartitionInterval.Day, 3);
        var existing = new[]
        {
            Day("events_2026_09_11", 11),
            Day("events_2026_09_12", 12),
            // The partition for September 13 has another name but the right bounds
            Day("events_manual", 13),
            new ExistingPartition("events_default", null, null)
        };

        // Act
        var missing = PartitionPlanner.FindMissing(required, existing);

        // Assert
        missing.Select(p => p.Name).Should().Equal("events_2026_09_14");
    }

    [Fact]
    public void FindMissing_ShouldTreatWiderPartitionAsCovering()
    {
        // Arrange: one monthly partition covers all required days
        var required = PartitionPlanner.RequiredPartitions("lab03.events", Now, PartitionInterval.Day, 3);
        var month = new ExistingPartition("events_2026_09",
            new DateTime(2026, 9, 1, 0, 0, 0, DateTimeKind.Utc), new DateTime(2026, 10, 1, 0, 0, 0, DateTimeKind.Utc));

        // Act
        var missing = PartitionPlanner.FindMissing(required, new[] { month });

        // Assert
        missing.Should().BeEmpty();
    }

    [Fact]
    public void Expired_ShouldReturnPartitionsOlderThanRetention()
    {
        // Arrange
        var existing = new[] { Day("events_2026_09_09", 9), Day("events_2026_09_10", 10), Day("events_2026_09_11", 11) };

        // Act: keep 1 past day, so everything that ends before September 10 goes
        var expired = PartitionPlanner.Expired(existing, Now, PartitionInterval.Day, 1);

        // Assert
        expired.Select(p => p.Name).Should().Equal("events_2026_09_09");
    }

    [Fact]
    public void Horizon_ShouldDescribePeriods()
    {
        PartitionPlanner.Horizon(PartitionInterval.Day, 3).Should().Be("3 days");
        PartitionPlanner.Horizon(PartitionInterval.Month, 3).Should().Be("3 months");
    }

    private static ExistingPartition Day(string name, int day) => new(
        name, new DateTime(2026, 9, day, 0, 0, 0, DateTimeKind.Utc), new DateTime(2026, 9, day + 1, 0, 0, 0, DateTimeKind.Utc));
}
