namespace TaskManager.Application.Interfaces;

/// <summary>
/// Delivers alerts to people (Telegram, email, ...).
/// </summary>
public interface IAlertNotifier
{
    /// <summary>
    /// Sends the message; throws if it could not be delivered.
    /// </summary>
    Task SendAsync(string message, CancellationToken cancellationToken = default);
}
