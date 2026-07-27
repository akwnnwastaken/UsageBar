using System.Text;

namespace UsageBar.Windows.Infrastructure.Process;

/// <summary>
/// Encodes an explicit argument array into the single command-line string
/// CreateProcessW requires.
///
/// This is <b>not</b> a shell command builder: the executable is always passed
/// separately as lpApplicationName, and every argument is quoted with the
/// documented CommandLineToArgvW rules so no argument can be reinterpreted as
/// another argument, a redirection or a second command. UsageBar never
/// concatenates user-controlled text into a command line by hand.
/// </summary>
internal static class WindowsCommandLine
{
    /// <summary>
    /// Builds the command line. <paramref name="executablePath"/> becomes argv[0]
    /// and is always quoted, so a path containing spaces cannot split.
    /// </summary>
    public static string Build(string executablePath, IReadOnlyList<string> arguments)
    {
        ArgumentException.ThrowIfNullOrEmpty(executablePath);
        ArgumentNullException.ThrowIfNull(arguments);

        var builder = new StringBuilder();
        AppendQuoted(builder, executablePath, alwaysQuote: true);
        foreach (var argument in arguments)
        {
            builder.Append(' ');
            AppendQuoted(builder, argument ?? string.Empty, alwaysQuote: false);
        }

        return builder.ToString();
    }

    /// <summary>Null-terminated buffer; CreateProcessW may write into it.</summary>
    public static char[] ToWritableBuffer(string commandLine)
    {
        var buffer = new char[commandLine.Length + 1];
        commandLine.CopyTo(0, buffer, 0, commandLine.Length);
        buffer[^1] = '\0';
        return buffer;
    }

    private static void AppendQuoted(StringBuilder builder, string argument, bool alwaysQuote)
    {
        var needsQuotes = alwaysQuote ||
                          argument.Length == 0 ||
                          argument.AsSpan().IndexOfAny(" \t\n\v\"") >= 0;

        if (!needsQuotes)
        {
            builder.Append(argument);
            return;
        }

        builder.Append('"');
        for (var index = 0; index < argument.Length; index++)
        {
            var backslashes = 0;
            while (index < argument.Length && argument[index] == '\\')
            {
                index++;
                backslashes++;
            }

            if (index == argument.Length)
            {
                // Backslashes before the closing quote must be doubled.
                builder.Append('\\', backslashes * 2);
                break;
            }

            if (argument[index] == '"')
            {
                // Backslashes before a literal quote are doubled, then the quote
                // itself is escaped.
                builder.Append('\\', (backslashes * 2) + 1);
            }
            else
            {
                builder.Append('\\', backslashes);
            }

            builder.Append(argument[index]);
        }

        builder.Append('"');
    }
}
