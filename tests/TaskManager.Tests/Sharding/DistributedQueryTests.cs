using FluentAssertions;
using Microsoft.Extensions.Logging.Abstractions;
using Moq;
using TaskManager.Application.Exceptions;
using TaskManager.Application.Interfaces;
using TaskManager.Application.Services;
using TaskManager.Application.Sharding;
using TaskManager.Domain.Entities;

namespace TaskManager.Tests.Sharding;

/// <summary>
/// Unit tests for merging results of distributed queries.
/// </summary>
public class DistributedQueryTests
{
    [Fact]
    public void MergeStatuses_ShouldAddCountsAndComputeAverageFromTotals()
    {
        // Shard 0: 10 tasks of 10 days on average; shard 1: 90 tasks of 1 day on average
        var merged = DistributedMerge.MergeStatuses(new[]
        {
            (IReadOnlyList<StatusAggregate>)new[] { new StatusAggregate(0, 10, 2, 100) },
            new[] { new StatusAggregate(0, 90, 3, 90) }
        });

        var pending = merged.Should().ContainSingle().Subject;
        pending.Count.Should().Be(100);
        pending.Overdue.Should().Be(5);
        // (100 + 90) / (10 + 90) = 1.9, while the mean of shard averages (10 + 1) / 2 = 5.5 is wrong
        pending.AverageAgeDays.Should().Be(1.9);
        pending.AverageOfShardAveragesDays.Should().Be(5.5);
    }

    [Fact]
    public void MergeNewest_ShouldEqualGlobalOrder_WhenEveryShardReturnsPrefixUpToPageEnd()
    {
        var random = new Random(7);
        var start = new DateTime(2026, 1, 1, 0, 0, 0, DateTimeKind.Utc);
        var all = Enumerable.Range(0, 3000)
            .Select(i => (Shard: random.Next(3), Task: new TaskItem
            {
                Id = Guid.NewGuid(), UserId = Guid.NewGuid(), Title = $"t{i}", CreatedAt = start.AddMinutes(random.Next(500_000))
            }))
            .ToList();
        const int page = 4, pageSize = 25;

        var shards = Enumerable.Range(0, 3).Select(s => (s, (IReadOnlyList<TaskItem>)all
            .Where(x => x.Shard == s).Select(x => x.Task)
            .OrderByDescending(t => t.CreatedAt).ThenByDescending(t => t.Id)
            .Take(page * pageSize).ToList()));

        var merged = DistributedMerge.MergeNewest(shards, (page - 1) * pageSize, pageSize);

        var expected = all.Select(x => x.Task)
            .OrderByDescending(t => t.CreatedAt).ThenByDescending(t => t.Id)
            .Skip((page - 1) * pageSize).Take(pageSize).Select(t => t.Id);
        merged.Select(r => r.Id).Should().Equal(expected);
    }

    [Fact]
    public void MergeNewest_FromOneShard_ShouldMissNewerTasksOfOtherShards()
    {
        var now = DateTime.UtcNow;
        var shard0 = new List<TaskItem> { Task(now.AddHours(-5)), Task(now.AddHours(-6)) };
        var shard1 = new List<TaskItem> { Task(now.AddHours(-1)), Task(now.AddHours(-2)) };

        var global = DistributedMerge.MergeNewest(new[] { (0, (IReadOnlyList<TaskItem>)shard0), (1, shard1) }, 0, 2);
        var onlyShard0 = DistributedMerge.MergeNewest(new[] { (0, (IReadOnlyList<TaskItem>)shard0) }, 0, 2);

        global.Select(r => r.Shard).Should().Equal(1, 1);
        onlyShard0.Select(r => r.Id).Should().NotIntersectWith(global.Select(r => r.Id));
    }

    [Fact]
    public async Task GetStats_ShouldFail_WhenShardIsDown_AndPartialIsNotAllowed()
    {
        var service = ServiceWithDeadShard();

        var act = () => service.GetStatsAsync(parallel: true, allowPartial: false);

        (await act.Should().ThrowAsync<ShardUnavailableException>()).Which.Shards.Should().Equal(2);
    }

    [Fact]
    public async Task GetStats_ShouldReturnMarkedPartialResult_WhenAllowed()
    {
        var service = ServiceWithDeadShard();

        var stats = await service.GetStatsAsync(parallel: false, allowPartial: true);

        stats.Partial.Should().BeTrue();
        stats.Total.Should().Be(200);
        stats.Shards.Should().HaveCount(3);
        stats.Shards.Single(s => s.Shard == 2).Available.Should().BeFalse();
    }

    private static DistributedTaskQueryService ServiceWithDeadShard()
    {
        var store = new Mock<IShardedTaskStore>();
        store.Setup(s => s.GetTopologyAsync(It.IsAny<CancellationToken>()))
            .ReturnsAsync(new ShardTopology(ShardStrategy.ConsistentHashing, 3, 500, DateTime.UtcNow));
        store.Setup(s => s.AggregateByStatusAsync(It.Is<int>(i => i < 2), It.IsAny<DateTime>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(new[] { new StatusAggregate(0, 100, 0, 100) });
        store.Setup(s => s.AggregateByStatusAsync(2, It.IsAny<DateTime>(), It.IsAny<CancellationToken>()))
            .ThrowsAsync(new ShardUnavailableException(new[] { 2 }));
        return new DistributedTaskQueryService(store.Object, NullLogger<DistributedTaskQueryService>.Instance);
    }

    private static TaskItem Task(DateTime createdAt) => new() { Id = Guid.NewGuid(), UserId = Guid.NewGuid(), Title = "t", CreatedAt = createdAt };
}
