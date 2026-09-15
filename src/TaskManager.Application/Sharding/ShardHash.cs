using System.Security.Cryptography;
using System.Text;

namespace TaskManager.Application.Sharding;

/// <summary>
/// Stable 64-bit hash used by both routers. It must give the same value in every process and on
/// every machine, so <see cref="object.GetHashCode"/> (randomized per process) cannot be used.
/// </summary>
public static class ShardHash
{
    /// <summary>
    /// Hashes a text key: the first 8 bytes of MD5 as an unsigned number.
    /// </summary>
    public static ulong Of(string key)
    {
        Span<byte> digest = stackalloc byte[MD5.HashSizeInBytes];
        MD5.HashData(Encoding.UTF8.GetBytes(key), digest);
        return BitConverter.ToUInt64(digest[..8]);
    }

    /// <summary>
    /// Hashes a shard key: the lower-case text form of the id, as it is stored in the database.
    /// </summary>
    public static ulong Of(Guid key) => Of(key.ToString("D"));
}
