namespace TaskManager.Application.Common;

/// <summary>
/// Sort order of a task list, parsed from the <c>sort</c> query parameter:
/// <c>created_at</c>, <c>due_date</c>, <c>priority</c> or <c>title</c>; a leading minus means descending.
/// </summary>
/// <param name="Field">The field to sort by.</param>
/// <param name="Descending">True to sort in descending order.</param>
public readonly record struct TaskSort(TaskSortField Field, bool Descending)
{
    /// <summary>
    /// Gets the default order: newest tasks first.
    /// </summary>
    public static TaskSort Default => new(TaskSortField.CreatedAt, true);

    /// <summary>
    /// Parses the <c>sort</c> query parameter. An empty value means <see cref="Default"/>.
    /// </summary>
    /// <param name="value">The raw value, for example <c>-created_at</c>.</param>
    /// <param name="sort">The parsed sort order.</param>
    /// <returns>True if the value is empty or names a known field; otherwise, false.</returns>
    public static bool TryParse(string? value, out TaskSort sort)
    {
        sort = Default;

        if (string.IsNullOrWhiteSpace(value))
        {
            return true;
        }

        var trimmed = value.Trim();
        var descending = trimmed.StartsWith('-');

        TaskSortField? field = trimmed.TrimStart('-').ToLowerInvariant() switch
        {
            "created_at" or "createdat" => TaskSortField.CreatedAt,
            "due_date" or "duedate" => TaskSortField.DueDate,
            "priority" => TaskSortField.Priority,
            "title" => TaskSortField.Title,
            _ => null
        };

        if (field is null)
        {
            return false;
        }

        sort = new TaskSort(field.Value, descending);
        return true;
    }
}
