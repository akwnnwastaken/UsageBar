namespace UsageBar.Windows.Infrastructure.Process;

/// <summary>
/// Accumulates process output up to a hard byte limit. Once the limit is
/// reached the capture stops growing and records that it overflowed, so a
/// provider that floods stdout can never exhaust UsageBar's memory.
/// </summary>
internal sealed class BoundedOutputCapture
{
    private readonly int _limit;
    private readonly object _gate = new();
    private readonly MemoryStream _buffer = new();
    private bool _exceeded;

    public BoundedOutputCapture(int limit) => _limit = Math.Max(0, limit);

    /// <summary>Appends a chunk. Returns false once the limit has been reached.</summary>
    public bool Append(ReadOnlySpan<byte> chunk)
    {
        lock (_gate)
        {
            if (chunk.IsEmpty)
            {
                return !_exceeded;
            }

            var remaining = Math.Max(0, _limit - (int)_buffer.Length);
            if (chunk.Length > remaining)
            {
                _buffer.Write(chunk[..remaining]);
                _exceeded = true;
            }
            else
            {
                _buffer.Write(chunk);
            }

            return !_exceeded;
        }
    }

    public (byte[] Data, bool Exceeded) Snapshot()
    {
        lock (_gate)
        {
            return (_buffer.ToArray(), _exceeded);
        }
    }

    public bool Exceeded
    {
        get
        {
            lock (_gate)
            {
                return _exceeded;
            }
        }
    }
}
