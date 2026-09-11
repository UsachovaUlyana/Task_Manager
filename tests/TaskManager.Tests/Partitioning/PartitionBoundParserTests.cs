using FluentAssertions;
using TaskManager.Infrastructure.Repositories;

namespace TaskManager.Tests.Partitioning;

/// <summary>
/// Unit tests for PartitionBoundParser.
/// </summary>
public class PartitionBoundParserTests
{
    [Theory]
    // timestamptz, session time zone UTC
    [InlineData("FOR VALUES FROM ('2026-09-01 00:00:00+00') TO ('2026-10-01 00:00:00+00')")]
    // timestamp without time zone
    [InlineData("FOR VALUES FROM ('2026-09-01 00:00:00') TO ('2026-10-01 00:00:00')")]
    // date
    [InlineData("FOR VALUES FROM ('2026-09-01') TO ('2026-10-01')")]
    public void Parse_ShouldReturnUtcBounds(string bound)
    {
        // Act
        var (from, to) = PartitionBoundParser.Parse(bound);

        // Assert
        from.Should().Be(new DateTime(2026, 9, 1, 0, 0, 0, DateTimeKind.Utc));
        to.Should().Be(new DateTime(2026, 10, 1, 0, 0, 0, DateTimeKind.Utc));
        from!.Value.Kind.Should().Be(DateTimeKind.Utc);
    }

    [Fact]
    public void Parse_ShouldConvertOffsetToUtc()
    {
        var (from, _) = PartitionBoundParser.Parse(
            "FOR VALUES FROM ('2026-09-01 00:00:00+03') TO ('2026-10-01 00:00:00+03')");

        from.Should().Be(new DateTime(2026, 8, 31, 21, 0, 0, DateTimeKind.Utc));
    }

    [Theory]
    [InlineData("DEFAULT")]
    [InlineData("FOR VALUES IN ('VIP')")]
    [InlineData("FOR VALUES WITH (modulus 4, remainder 0)")]
    [InlineData("FOR VALUES FROM (MINVALUE) TO ('2026-01-01 00:00:00')")]
    [InlineData(null)]
    public void Parse_ShouldReturnNull_ForNonTimeRanges(string? bound)
    {
        var (from, to) = PartitionBoundParser.Parse(bound);

        from.Should().BeNull();
        to.Should().BeNull();
    }
}
