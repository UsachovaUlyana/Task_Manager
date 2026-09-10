using FluentAssertions;
using TaskManager.Application.Common;

namespace TaskManager.Tests.Common;

/// <summary>
/// Unit tests for parsing the task list sort parameter.
/// </summary>
public class TaskSortTests
{
    [Theory]
    [InlineData(null, TaskSortField.CreatedAt, true)]
    [InlineData("", TaskSortField.CreatedAt, true)]
    [InlineData("created_at", TaskSortField.CreatedAt, false)]
    [InlineData("-created_at", TaskSortField.CreatedAt, true)]
    [InlineData("-due_date", TaskSortField.DueDate, true)]
    [InlineData("priority", TaskSortField.Priority, false)]
    [InlineData("Title", TaskSortField.Title, false)]
    public void TryParse_ShouldParseKnownValues(string? value, TaskSortField field, bool descending)
    {
        // Act
        var parsed = TaskSort.TryParse(value, out var sort);

        // Assert
        parsed.Should().BeTrue();
        sort.Should().Be(new TaskSort(field, descending));
    }

    [Theory]
    [InlineData("password_hash")]
    [InlineData("-")]
    public void TryParse_ShouldRejectUnknownFields(string value)
    {
        // Act
        var parsed = TaskSort.TryParse(value, out _);

        // Assert
        parsed.Should().BeFalse();
    }
}
