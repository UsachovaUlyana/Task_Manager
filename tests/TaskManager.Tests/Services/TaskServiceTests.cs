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
/// Unit tests for TaskService.
/// </summary>
public class TaskServiceTests
{
    [Fact]
    public async Task GetTasksAsync_ShouldPassDueDatesToRepositoryAsUtc()
    {
        // Arrange
        var repository = new Mock<ITaskRepository>();
        repository
            .Setup(r => r.GetAllFilteredAsync(
                It.IsAny<TaskItemStatus?>(), It.IsAny<TaskPriority?>(), It.IsAny<Guid?>(),
                It.IsAny<DateTime?>(), It.IsAny<DateTime?>(), It.IsAny<int>(), It.IsAny<int>(),
                It.IsAny<TaskSort?>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(new PagedResult<TaskItem> { Items = new List<TaskItem>() });

        var service = new TaskService(
            repository.Object, Mock.Of<ITaskTagRepository>(), Mock.Of<ICacheService>(), NullLogger<TaskService>.Instance);

        // ?dueDateFrom=2026-01-01 is bound without a time zone
        var filter = new TaskFilterRequest
        {
            DueDateFrom = new DateTime(2026, 1, 1),
            DueDateTo = new DateTime(2026, 1, 8)
        };

        // Act
        await service.GetTasksAsync(filter);

        // Assert
        repository.Verify(r => r.GetAllFilteredAsync(
            null, null, null,
            It.Is<DateTime?>(d => d!.Value.Kind == DateTimeKind.Utc && d.Value == new DateTime(2026, 1, 1)),
            It.Is<DateTime?>(d => d!.Value.Kind == DateTimeKind.Utc && d.Value == new DateTime(2026, 1, 8)),
            1, 10, It.IsAny<TaskSort?>(), It.IsAny<CancellationToken>()), Times.Once);
    }
}
