using System.Net.Http.Json;
using Microsoft.Extensions.Logging;
using TaskManager.Application.Interfaces;

namespace TaskManager.Infrastructure.Services;

/// <summary>
/// Telegram bot settings ("Alerts:Telegram" section). The token must not be committed:
/// in Docker it comes from the TELEGRAM_BOT_TOKEN variable of the local .env file.
/// </summary>
public class TelegramOptions
{
    /// <summary>
    /// Configuration section name.
    /// </summary>
    public const string SectionName = "Alerts:Telegram";

    /// <summary>
    /// Gets or sets the bot token issued by @BotFather.
    /// </summary>
    public string BotToken { get; set; } = string.Empty;

    /// <summary>
    /// Gets or sets the chat that receives alerts.
    /// </summary>
    public string ChatId { get; set; } = string.Empty;

    /// <summary>
    /// Gets a value indicating whether both the token and the chat are set.
    /// </summary>
    public bool IsConfigured => !string.IsNullOrWhiteSpace(BotToken) && !string.IsNullOrWhiteSpace(ChatId);
}

/// <summary>
/// Sends alerts through the Telegram Bot API. Without a token and chat the alert is only written to the log.
/// </summary>
public class TelegramAlertNotifier : IAlertNotifier
{
    private readonly HttpClient _httpClient;
    private readonly TelegramOptions _options;
    private readonly ILogger<TelegramAlertNotifier> _logger;

    /// <summary>
    /// Initializes a new instance of the <see cref="TelegramAlertNotifier"/> class.
    /// </summary>
    public TelegramAlertNotifier(HttpClient httpClient, TelegramOptions options, ILogger<TelegramAlertNotifier> logger)
    {
        _httpClient = httpClient;
        _options = options;
        _logger = logger;
    }

    /// <inheritdoc/>
    public async Task SendAsync(string message, CancellationToken cancellationToken = default)
    {
        if (!_options.IsConfigured)
        {
            _logger.LogWarning("Telegram is not configured, the alert is only logged:\n{Message}", message);
            return;
        }

        var response = await _httpClient.PostAsJsonAsync(
            $"https://api.telegram.org/bot{_options.BotToken}/sendMessage",
            new { chat_id = _options.ChatId, text = message },
            cancellationToken);

        if (!response.IsSuccessStatusCode)
        {
            var body = await response.Content.ReadAsStringAsync(cancellationToken);
            throw new InvalidOperationException($"Telegram API returned {(int)response.StatusCode}: {body}");
        }

        _logger.LogInformation("Alert sent to Telegram chat {ChatId}", _options.ChatId);
    }
}
