using FluentAssertions;
using Microsoft.Extensions.Logging.Abstractions;
using TaskManager.Application.Interfaces;
using TaskManager.Application.Partitioning;
using TaskManager.Application.Services;

namespace TaskManager.Tests.Partitioning;

/// <summary>
/// Unit tests for PartitionMaintenanceService: the partition job and the check with alerts.
/// </summary>
public class PartitionMaintenanceServiceTests
{
    private const string Events = "lab03.events";

    private readonly FakePartitionRepository _repository = new();
    private readonly FakeNotifier _notifier = new();
    private readonly FixedTimeProvider _time = new(new DateTime(2026, 9, 11, 22, 0, 0, DateTimeKind.Utc));
    private readonly PartitioningOptions _options = new()
    {
        Tables = { new PartitionedTableOptions { Table = Events, Interval = PartitionInterval.Day, PeriodsAhead = 3 } }
    };

    public PartitionMaintenanceServiceTests()
    {
        _repository.AddTable(Events, "events_2026_09_09", "events_2026_09_10", "events_2026_09_11");
    }

    [Fact]
    public async Task EnsurePartitionsAsync_ShouldCreateMissingPartitionsForHorizonAndReserve()
    {
        // Act
        var result = await CreateService().EnsurePartitionsAsync();

        // Assert: 3 days ahead required by the check plus 1 day of reserve
        result.Status.Should().Be(PartitionStatus.Ok);
        result.Tables[0].CreatedPartitions.Should().Equal(
            "events_2026_09_12", "events_2026_09_13", "events_2026_09_14", "events_2026_09_15");
        _repository.Names(Events).Should().HaveCount(7);
    }

    [Fact]
    public async Task CheckAsync_ShouldStayOk_AfterMidnightBeforeNightlyJob()
    {
        // Arrange: the job ran on September 11, now it is 00:30 on September 12, the next job runs at 01:00
        var service = CreateService();
        await service.EnsurePartitionsAsync();
        _time.Advance(TimeSpan.FromHours(2.5));

        // Act
        var result = await service.CheckAsync(notify: true);

        // Assert: the horizon moved to September 15, which the job created in reserve
        result.Status.Should().Be(PartitionStatus.Ok);
        result.Tables[0].RequiredPartitions.Should().EndWith("events_2026_09_15");
        _notifier.Messages.Should().BeEmpty();
    }

    [Fact]
    public async Task EnsurePartitionsAsync_ShouldBeIdempotent()
    {
        // Arrange
        var service = CreateService();
        await service.EnsurePartitionsAsync();

        // Act
        var second = await service.EnsurePartitionsAsync();

        // Assert
        second.Tables[0].CreatedPartitions.Should().BeEmpty();
        second.Tables[0].MissingPartitions.Should().BeEmpty();
        _repository.Names(Events).Should().HaveCount(7);
    }

    [Fact]
    public async Task EnsurePartitionsAsync_ShouldDropPartitionsOlderThanRetention()
    {
        // Arrange
        _options.Tables[0].RetentionPeriods = 1;

        // Act
        var result = await CreateService().EnsurePartitionsAsync();

        // Assert
        result.Tables[0].DroppedPartitions.Should().Equal("events_2026_09_09");
        _repository.Names(Events).Should().NotContain("events_2026_09_09").And.Contain("events_2026_09_10");
    }

    [Fact]
    public async Task EnsurePartitionsAsync_ShouldSkipTableThatIsNotPartitioned()
    {
        // Arrange
        _options.Tables.Add(new PartitionedTableOptions { Table = "missing_table" });

        // Act
        var result = await CreateService().EnsurePartitionsAsync();

        // Assert
        result.Tables.Single(t => t.Table == "missing_table").Status.Should().Be(PartitionStatus.Skipped);
        result.Status.Should().Be(PartitionStatus.Ok);
    }

    [Fact]
    public async Task CheckAsync_ShouldAlertOnceAndSendRecovery()
    {
        // Arrange: the job has created the horizon, then someone drops a future partition
        var service = CreateService();
        await service.EnsurePartitionsAsync();
        _repository.Drop(Events, "events_2026_09_14");

        // Act & Assert: 22:00 CRITICAL → alert
        var first = await service.CheckAsync(notify: true);
        first.Status.Should().Be(PartitionStatus.Critical);
        first.Tables[0].MissingPartitions.Should().Equal("events_2026_09_14");
        first.Tables[0].Alert.Should().Be("critical alert sent");
        _notifier.Messages.Should().ContainSingle().Which.Should().Contain("events_2026_09_14");

        // 22:05 still CRITICAL → no new alert
        _time.Advance(TimeSpan.FromMinutes(5));
        var second = await service.CheckAsync(notify: true);
        second.Tables[0].Alert.Should().Be("already notified");
        _notifier.Messages.Should().HaveCount(1);

        // The job restores the partition; 22:10 OK → recovery
        await service.EnsurePartitionsAsync();
        _time.Advance(TimeSpan.FromMinutes(5));
        var third = await service.CheckAsync(notify: true);
        third.Status.Should().Be(PartitionStatus.Ok);
        third.Tables[0].Alert.Should().Be("recovery sent");
        _notifier.Messages.Should().HaveCount(2);
        _notifier.Messages[1].Should().Contain("Partition check OK");

        // 22:15 OK → nothing
        _time.Advance(TimeSpan.FromMinutes(5));
        var fourth = await service.CheckAsync(notify: true);
        fourth.Tables[0].Alert.Should().BeNull();
        _notifier.Messages.Should().HaveCount(2);
    }

    [Fact]
    public async Task CheckAsync_ShouldRetryAlertThatWasNotDelivered()
    {
        // Arrange
        var service = CreateService();
        _notifier.FailNext = true;

        // Act
        var first = await service.CheckAsync(notify: true);
        var second = await service.CheckAsync(notify: true);

        // Assert
        first.Tables[0].Alert.Should().Be("failed");
        second.Tables[0].Alert.Should().Be("critical alert sent");
        _notifier.Messages.Should().ContainSingle();
    }

    [Fact]
    public async Task CheckAsync_ShouldAlertAgain_WhenAnotherPartitionGoesMissing()
    {
        // Arrange
        var service = CreateService();
        await service.EnsurePartitionsAsync();
        _repository.Drop(Events, "events_2026_09_14");
        await service.CheckAsync(notify: true);

        // Act
        _repository.Drop(Events, "events_2026_09_13");
        var result = await service.CheckAsync(notify: true);

        // Assert
        result.Tables[0].MissingPartitions.Should().Equal("events_2026_09_13", "events_2026_09_14");
        result.Tables[0].Alert.Should().Be("critical alert sent");
        _notifier.Messages.Should().HaveCount(2);
    }

    [Fact]
    public async Task CheckAsync_WithoutNotify_ShouldNotSendOrSaveState()
    {
        // Act
        var result = await CreateService().CheckAsync(notify: false);

        // Assert
        result.Status.Should().Be(PartitionStatus.Critical);
        result.Tables[0].Alert.Should().BeNull();
        _notifier.Messages.Should().BeEmpty();
        _repository.States.Should().BeEmpty();
    }

    private PartitionMaintenanceService CreateService() =>
        new(_repository, _notifier, _options, _time, NullLogger<PartitionMaintenanceService>.Instance);

    private sealed class FixedTimeProvider : TimeProvider
    {
        private DateTimeOffset _now;

        public FixedTimeProvider(DateTime now) => _now = now;

        public override DateTimeOffset GetUtcNow() => _now;

        public void Advance(TimeSpan by) => _now += by;
    }

    private sealed class FakeNotifier : IAlertNotifier
    {
        public List<string> Messages { get; } = new();

        public bool FailNext { get; set; }

        public Task SendAsync(string message, CancellationToken cancellationToken = default)
        {
            if (FailNext)
            {
                FailNext = false;
                throw new HttpRequestException("Telegram is unavailable");
            }

            Messages.Add(message);
            return Task.CompletedTask;
        }
    }

    private sealed class FakePartitionRepository : IPartitionRepository
    {
        private readonly Dictionary<string, List<ExistingPartition>> _tables = new();

        public Dictionary<string, PartitionAlertState> States { get; } = new();

        public void AddTable(string table, params string[] dayPartitions)
        {
            _tables[table] = dayPartitions
                .Select(name =>
                {
                    var day = DateTime.SpecifyKind(DateTime.ParseExact(name[^10..], "yyyy_MM_dd", null), DateTimeKind.Utc);
                    return new ExistingPartition(name, day, day.AddDays(1));
                })
                .ToList();
        }

        public IEnumerable<string> Names(string table) => _tables[table].Select(p => p.Name);

        public void Drop(string table, string name) => _tables[table].RemoveAll(p => p.Name == name);

        public Task<bool> IsPartitionedAsync(string table, CancellationToken cancellationToken = default) =>
            Task.FromResult(_tables.ContainsKey(table));

        public Task<IReadOnlyList<ExistingPartition>> GetPartitionsAsync(string table, CancellationToken cancellationToken = default) =>
            Task.FromResult<IReadOnlyList<ExistingPartition>>(_tables[table].ToList());

        public Task CreatePartitionAsync(string table, PartitionRange partition, CancellationToken cancellationToken = default)
        {
            if (_tables[table].All(p => p.Name != partition.Name))
            {
                _tables[table].Add(new ExistingPartition(partition.Name, partition.From, partition.To));
            }

            return Task.CompletedTask;
        }

        public Task DropPartitionAsync(string table, string partitionName, CancellationToken cancellationToken = default)
        {
            Drop(table, partitionName);
            return Task.CompletedTask;
        }

        public Task<PartitionAlertState?> GetAlertStateAsync(string table, CancellationToken cancellationToken = default) =>
            Task.FromResult(States.TryGetValue(table, out var state) ? state : null);

        public Task SaveAlertStateAsync(PartitionAlertState state, CancellationToken cancellationToken = default)
        {
            States[state.Table] = state;
            return Task.CompletedTask;
        }
    }
}
