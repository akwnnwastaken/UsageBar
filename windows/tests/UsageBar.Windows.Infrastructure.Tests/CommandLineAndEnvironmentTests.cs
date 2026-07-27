using System.Runtime.InteropServices;
using System.Runtime.Versioning;
using UsageBar.Windows.Infrastructure.Process;
using Xunit;

namespace UsageBar.Windows.Infrastructure.Tests;

/// <summary>
/// The command line handed to CreateProcessW and the environment a provider
/// sees. Both are built from explicit inputs — there is no shell to reinterpret
/// them — and these tests pin the quoting rules that make that true.
/// </summary>
[SupportedOSPlatform("windows")]
public sealed class CommandLineAndEnvironmentTests
{
    [Fact]
    public void TheExecutableIsAlwaysQuoted()
    {
        Assert.Equal(
            @"""C:\Program Files\codex\codex.exe""",
            WindowsCommandLine.Build(@"C:\Program Files\codex\codex.exe", Array.Empty<string>()));
    }

    [Fact]
    public void SimpleArgumentsAreNotQuotedUnnecessarily()
    {
        Assert.Equal(
            @"""C:\codex.exe"" app-server --stdio",
            WindowsCommandLine.Build(@"C:\codex.exe", new[] { "app-server", "--stdio" }));
    }

    [Theory]
    // Spaces force quoting.
    [InlineData(new[] { "two words" }, @"""C:\a.exe"" ""two words""")]
    // An empty argument must survive as an empty argument.
    [InlineData(new[] { "" }, @"""C:\a.exe"" """"")]
    // Embedded quotes are escaped, never dropped.
    [InlineData(new[] { "say \"hi\"" }, @"""C:\a.exe"" ""say \""hi\""""")]
    // An argument that needs no quoting is passed through as-is, trailing
    // backslash included: outside quotes a backslash is already literal.
    [InlineData(new[] { @"C:\path\" }, @"""C:\a.exe"" C:\path\")]
    // Inside quotes a trailing backslash must be doubled, or it would escape the
    // closing quote and swallow the next argument.
    [InlineData(new[] { @"C:\my path\", "--stdio" }, @"""C:\a.exe"" ""C:\my path\\"" --stdio")]
    // Tabs count as separators too.
    [InlineData(new[] { "a\tb" }, "\"C:\\a.exe\" \"a\tb\"")]
    public void ArgumentsAreQuotedWithTheDocumentedRules(string[] arguments, string expected)
    {
        Assert.Equal(expected, WindowsCommandLine.Build(@"C:\a.exe", arguments));
    }

    /// <summary>
    /// The round trip that matters: whatever the encoder produces, Windows must
    /// split back into exactly the arguments that went in.
    /// </summary>
    [WindowsTheory]
    [InlineData((object)new[] { "app-server", "--stdio" })]
    [InlineData((object)new[] { "two words", "--disable", "apps" })]
    [InlineData((object)new[] { @"C:\Users\a b\codex.js", "-p", "/usage" })]
    [InlineData((object)new[] { "say \"hi\"", "a\\\\b", "" })]
    [InlineData((object)new[] { "trailing\\", "trailing space\\", "&& echo pwned", "| more", "> out.txt" })]
    public void QuotedArgumentsRoundTripThroughCommandLineToArgv(string[] arguments)
    {
        var commandLine = WindowsCommandLine.Build(@"C:\a.exe", arguments);

        Assert.Equal(
            new[] { @"C:\a.exe" }.Concat(arguments),
            SplitWithWindows(commandLine));
    }

    [Fact]
    public void TheEnvironmentBlockIsSortedAndDoubleNullTerminated()
    {
        var block = ProviderProcessEnvironment.ToEnvironmentBlock(
            new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
            {
                ["ZED"] = "3",
                ["alpha"] = "1",
                ["Beta"] = "2"
            });

        var text = new string(block);

        Assert.Equal("alpha=1\0Beta=2\0ZED=3\0\0", text);
    }

    [Fact]
    public void MalformedVariableNamesAreDroppedFromTheBlock()
    {
        var block = ProviderProcessEnvironment.ToEnvironmentBlock(
            new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
            {
                ["GOOD"] = "1",
                ["BAD=NAME"] = "2"
            });

        Assert.Equal("GOOD=1\0\0", new string(block));
    }

    [WindowsFact]
    public void TheProviderEnvironmentDropsUnrelatedVariablesAndRebuildsPath()
    {
        Environment.SetEnvironmentVariable("USAGEBAR_UNRELATED", "leak");
        try
        {
            var environment = ProviderProcessEnvironment.Build();

            Assert.False(environment.ContainsKey("USAGEBAR_UNRELATED"));
            Assert.True(environment.ContainsKey("SystemRoot"));
            Assert.True(environment.ContainsKey("PATH"));

            // PATH is rebuilt from system locations, so a directory the user
            // prepended to their own PATH cannot resolve a provider.
            var systemRoot = Environment.GetEnvironmentVariable("SystemRoot") ?? @"C:\Windows";
            foreach (var entry in environment["PATH"].Split(';'))
            {
                Assert.StartsWith(systemRoot, entry, StringComparison.OrdinalIgnoreCase);
            }

            // Providers get UsageBar's private directory as their temp folder.
            Assert.Equal(ProviderProcessEnvironment.WorkingDirectory, environment["TEMP"]);
        }
        finally
        {
            Environment.SetEnvironmentVariable("USAGEBAR_UNRELATED", null);
        }
    }

    [WindowsFact]
    public void TheWorkingDirectoryIsApplicationOwnedAndExists()
    {
        var directory = ProviderProcessEnvironment.WorkingDirectory;

        Assert.True(Directory.Exists(directory));
        Assert.Contains("UsageBar", directory, StringComparison.OrdinalIgnoreCase);
        Assert.NotEqual(
            Directory.GetCurrentDirectory().TrimEnd(Path.DirectorySeparatorChar),
            directory.TrimEnd(Path.DirectorySeparatorChar),
            StringComparer.OrdinalIgnoreCase);
    }

    /// <summary>
    /// Regression guard: a fixture path handed to a child process must use
    /// native separators only. .NET happily opens a mixed path, but a Windows
    /// command-line tool reads a <c>/segment</c> as a switch and fails.
    /// </summary>
    [WindowsFact]
    public void FixturePathsUseNativeSeparators()
    {
        var path = Fixtures.Path("codex/five-hour-and-weekly.jsonl");

        Assert.DoesNotContain('/', path);
        Assert.True(Path.IsPathFullyQualified(path));
        Assert.True(File.Exists(path));
    }

    [Fact]
    public void BoundedCaptureStopsAtItsLimit()
    {
        var capture = new BoundedOutputCapture(4);

        Assert.True(capture.Append(new byte[] { 1, 2, 3 }));
        Assert.False(capture.Append(new byte[] { 4, 5 }));

        var (data, exceeded) = capture.Snapshot();
        Assert.Equal(new byte[] { 1, 2, 3, 4 }, data);
        Assert.True(exceeded);

        // Once over the limit it stays over and stops growing.
        Assert.False(capture.Append(new byte[] { 6 }));
        Assert.Equal(4, capture.Snapshot().Data.Length);
    }

    [Fact]
    public void BoundedCaptureHandlesEmptyChunksAndAZeroLimit()
    {
        var capture = new BoundedOutputCapture(0);
        Assert.True(capture.Append(ReadOnlySpan<byte>.Empty));
        Assert.False(capture.Append(new byte[] { 1 }));
        Assert.Empty(capture.Snapshot().Data);
    }

    private static IEnumerable<string> SplitWithWindows(string commandLine)
    {
        var argv = CommandLineToArgvW(commandLine, out var count);
        if (argv == IntPtr.Zero)
        {
            throw new InvalidOperationException("CommandLineToArgvW failed.");
        }

        try
        {
            var arguments = new string[count];
            for (var index = 0; index < count; index++)
            {
                var pointer = Marshal.ReadIntPtr(argv, index * IntPtr.Size);
                arguments[index] = Marshal.PtrToStringUni(pointer) ?? string.Empty;
            }

            return arguments;
        }
        finally
        {
            LocalFree(argv);
        }
    }

    [DllImport("shell32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern IntPtr CommandLineToArgvW(string lpCmdLine, out int pNumArgs);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr LocalFree(IntPtr hMem);
}
