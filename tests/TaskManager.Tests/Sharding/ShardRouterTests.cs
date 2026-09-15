using System.Security.Cryptography;
using System.Text;
using FluentAssertions;
using TaskManager.Application.Sharding;

namespace TaskManager.Tests.Sharding;

/// <summary>
/// Unit tests for the shard routers and the rebalance planner.
/// </summary>
public class ShardRouterTests
{
    private static readonly IReadOnlyList<Guid> Keys = CreateKeys(100_000);

    [Fact]
    public void Hash_ShouldBeStableAndEqualToMd5Prefix()
    {
        var key = Guid.Parse("335fc496-f143-433c-b8b5-48277f10419e");
        var expected = BitConverter.ToUInt64(MD5.HashData(Encoding.UTF8.GetBytes(key.ToString("D"))), 0);

        ShardHash.Of(key).Should().Be(expected).And.Be(ShardHash.Of(key));
    }

    [Fact]
    public void Modulo_ShouldBeHashRemainder()
    {
        var router = new ModuloShardRouter(3);

        foreach (var key in Keys.Take(100))
        {
            router.GetShard(key).Should().Be((int)(ShardHash.Of(key) % 3));
        }
    }

    [Theory]
    [InlineData(3)]
    [InlineData(4)]
    public void BothStrategies_ShouldSplitRandomKeysEvenly(int shards)
    {
        // hash % N is almost ideal; the ring depends on where the virtual nodes happen to land,
        // so even with 200 points per shard one shard can be over 10% above the average
        MaxToAverage(new ModuloShardRouter(shards)).Should().BeLessThan(1.02);
        MaxToAverage(new ConsistentHashRouter(shards, 200)).Should().BeLessThan(1.15);
    }

    private static double MaxToAverage(IShardRouter router)
    {
        var sizes = Keys.GroupBy(router.GetShard).Select(g => g.Count()).ToList();
        sizes.Should().HaveCount(router.ShardCount);
        return sizes.Max() / (Keys.Count / (double)router.ShardCount);
    }

    [Fact]
    public void Modulo_ThreeToFour_ShouldMoveAboutThreeQuartersOfKeys()
    {
        var moved = Moved(new ModuloShardRouter(3), new ModuloShardRouter(4));

        // A key stays only when hash % 3 == hash % 4, that is hash % 12 is 0, 1 or 2: 3 of 12 cases
        moved.Should().BeInRange(0.74, 0.76);
    }

    [Fact]
    public void ConsistentHashing_ThreeToFour_ShouldMoveAboutQuarterOnlyToNewShard()
    {
        var before = new ConsistentHashRouter(3, 100);
        var after = new ConsistentHashRouter(4, 100);

        Moved(before, after).Should().BeInRange(0.18, 0.32);
        Keys.Where(k => before.GetShard(k) != after.GetShard(k))
            .Select(after.GetShard)
            .Distinct()
            .Should().Equal(3);
    }

    [Fact]
    public void ConsistentHashing_RemovingShard_ShouldMoveOnlyItsKeys()
    {
        var before = new ConsistentHashRouter(4, 100);
        var after = new ConsistentHashRouter(3, 100);

        Keys.Where(k => before.GetShard(k) != after.GetShard(k))
            .Select(before.GetShard)
            .Distinct()
            .Should().Equal(3);
    }

    [Fact]
    public void MoreVirtualNodes_ShouldMakeRingMoreEven()
    {
        var counts = Keys.ToDictionary(k => k, _ => 1L);

        var one = ShardPlanner.Distribute(counts, new ConsistentHashRouter(3, 1));
        var many = ShardPlanner.Distribute(counts, new ConsistentHashRouter(3, 500));

        many.DeviationPercent.Should().BeLessThan(one.DeviationPercent);
        many.MaxToAverage.Should().BeLessThan(1.1);
    }

    [Fact]
    public void Plan_ShouldCountRecordsOfMovedKeys()
    {
        var counts = Keys.Take(1000).Select((k, i) => (k, (long)(i % 5 + 1))).ToDictionary(x => x.k, x => x.Item2);

        var plan = ShardPlanner.Plan(counts, new ModuloShardRouter(3), new ModuloShardRouter(4));

        plan.TotalKeys.Should().Be(1000);
        plan.TotalRecords.Should().Be(counts.Values.Sum());
        plan.MovedRecords.Should().Be(counts
            .Where(c => new ModuloShardRouter(3).GetShard(c.Key) != new ModuloShardRouter(4).GetShard(c.Key))
            .Sum(c => c.Value));
        plan.Moves.Values.Sum().Should().Be(plan.MovedRecords);
        plan.After.Shards.Sum(s => s.Records).Should().Be(plan.TotalRecords);
    }

    private static double Moved(IShardRouter before, IShardRouter after) =>
        Keys.Count(k => before.GetShard(k) != after.GetShard(k)) / (double)Keys.Count;

    private static IReadOnlyList<Guid> CreateKeys(int count)
    {
        var random = new Random(42);
        var bytes = new byte[16];
        return Enumerable.Range(0, count).Select(_ =>
        {
            random.NextBytes(bytes);
            return new Guid(bytes);
        }).ToList();
    }
}
