using FluentAssertions;
using Microsoft.Extensions.Logging.Abstractions;
using Moq;
using TaskManager.Application.Common;
using TaskManager.Application.DTOs.Tasks;
using TaskManager.Application.Interfaces;
using TaskManager.Application.Services;
using TaskManager.Domain.Entities;
using TaskManager.Domain.Enums;

namespace TaskManager.Tests.Services;

/// <summary>
/// Unit tests for TaskService, including the split between the primary and the read replica.
/// </summary>
public class TaskServiceTests
{
    private readonly Mock<ITaskRepository> _primary = new();
    private readonly Mock<ITaskReadRepository> _replica = new();

    [Fact]
    public async Task GetTasksAsync_ShouldPassDueDatesToReplicaAsUtc()
    {
        // Arrange
        SetupReplicaList();
        var service = CreateService();

        // ?dueDateFrom=2026-01-01 is bound without a time zone
        var filter = new TaskFilterRequest
        {
            DueDateFrom = new DateTime(2026, 1, 1),
            DueDateTo = new DateTime(2026, 1, 8)
        };

        // Act
        await service.GetTasksAsync(filter);

        // Assert
        _replica.Verify(r => r.GetAllFilteredAsync(
            null, null, null,
            It.Is<DateTime?>(d => d!.Value.Kind == DateTimeKind.Utc && d.Value == new DateTime(2026, 1, 1)),
            It.Is<DateTime?>(d => d!.Value.Kind == DateTimeKind.Utc && d.Value == new DateTime(2026, 1, 8)),
            1, 10, It.IsAny<TaskSort?>(), null, null, It.IsAny<CancellationToken>()), Times.Once);
    }

    [Fact]
    public async Task GetTasksAsync_ShouldPassCreatedRangeToReplicaAsUtc()
    {
        // Arrange
        SetupReplicaList();
        var service = CreateService();
        var userId = Guid.NewGuid();

        // ?createdFrom=2026-09-01&createdTo=2026-09-30: the range the partitions of tasks are pruned by
        var filter = new TaskFilterRequest
        {
            CreatedFrom = new DateTime(2026, 9, 1),
            CreatedTo = new DateTime(2026, 9, 30)
        };

        // Act
        await service.GetTasksAsync(filter, userId);

        // Assert
        _replica.Verify(r => r.GetByUserIdAsync(
            userId, null, null, null, null, null, 1, 10, It.IsAny<TaskSort?>(),
            It.Is<DateTime?>(d => d!.Value.Kind == DateTimeKind.Utc && d.Value == new DateTime(2026, 9, 1)),
            It.Is<DateTime?>(d => d!.Value.Kind == DateTimeKind.Utc && d.Value == new DateTime(2026, 9, 30)),
            It.IsAny<CancellationToken>()), Times.Once);
    }

    [Fact]
    public async Task GetTasksAsync_ShouldNotTouchThePrimary()
    {
        // Arrange
        SetupReplicaList();
        var service = CreateService();

        // Act
        await service.GetTasksAsync(new TaskFilterRequest());

        // Assert: the list of tasks is served by the replica only
        _primary.Verify(r => r.GetAllFilteredAsync(
            It.IsAny<TaskItemStatus?>(), It.IsAny<TaskPriority?>(), It.IsAny<Guid?>(),
            It.IsAny<DateTime?>(), It.IsAny<DateTime?>(), It.IsAny<int>(), It.IsAny<int>(),
            It.IsAny<TaskSort?>(), It.IsAny<DateTime?>(), It.IsAny<DateTime?>(),
            It.IsAny<CancellationToken>()), Times.Never);
    }

    [Fact]
    public async Task GetStatusStatsAsync_ShouldReadFromReplica()
    {
        // Arrange
        _replica
            .Setup(r => r.GetStatusStatsAsync(It.IsAny<Guid?>(), It.IsAny<DateTime>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(new List<TaskStatusCount>
            {
                new() { Status = TaskItemStatus.Pending, Count = 3, OverdueCount = 1 }
            });
        var service = CreateService();

        // Act
        var stats = await service.GetStatusStatsAsync();

        // Assert
        stats.Should().ContainSingle().Which.Count.Should().Be(3);
        _primary.Verify(r => r.GetStatusStatsAsync(
            It.IsAny<Guid?>(), It.IsAny<DateTime>(), It.IsAny<CancellationToken>()), Times.Never);
    }

    [Fact]
    public async Task CreateAsync_ShouldWriteToPrimaryAndReadItBackFromPrimary()
    {
        // Arrange
        _primary
            .Setup(r => r.AddAsync(It.IsAny<TaskItem>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync((TaskItem task, CancellationToken _) => task);
        _primary
            .Setup(r => r.GetByIdWithDetailsAsync(It.IsAny<Guid>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(new TaskItem { Id = Guid.NewGuid(), Title = "Написать отчёт" });
        var service = CreateService();

        // Act
        var created = await service.CreateAsync(new CreateTaskRequest { Title = "Написать отчёт" }, Guid.NewGuid());

        // Assert: the write and the read right after it go to the primary,
        // otherwise the client could get a 404 because of replication lag
        created.Title.Should().Be("Написать отчёт");
        _primary.Verify(r => r.AddAsync(It.IsAny<TaskItem>(), It.IsAny<CancellationToken>()), Times.Once);
        _primary.Verify(r => r.GetByIdWithDetailsAsync(It.IsAny<Guid>(), It.IsAny<CancellationToken>()), Times.Once);
        _replica.VerifyNoOtherCalls();
    }

    private TaskService CreateService() => new(
        _primary.Object, _replica.Object, Mock.Of<ITaskTagRepository>(), Mock.Of<ICacheService>(),
        NullLogger<TaskService>.Instance);

    private void SetupReplicaList()
    {
        _replica
            .Setup(r => r.GetAllFilteredAsync(
                It.IsAny<TaskItemStatus?>(), It.IsAny<TaskPriority?>(), It.IsAny<Guid?>(),
                It.IsAny<DateTime?>(), It.IsAny<DateTime?>(), It.IsAny<int>(), It.IsAny<int>(),
                It.IsAny<TaskSort?>(), It.IsAny<DateTime?>(), It.IsAny<DateTime?>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(new PagedResult<TaskItem> { Items = new List<TaskItem>() });
        _replica
            .Setup(r => r.GetByUserIdAsync(
                It.IsAny<Guid>(), It.IsAny<TaskItemStatus?>(), It.IsAny<TaskPriority?>(), It.IsAny<Guid?>(),
                It.IsAny<DateTime?>(), It.IsAny<DateTime?>(), It.IsAny<int>(), It.IsAny<int>(),
                It.IsAny<TaskSort?>(), It.IsAny<DateTime?>(), It.IsAny<DateTime?>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(new PagedResult<TaskItem> { Items = new List<TaskItem>() });
    }
}
