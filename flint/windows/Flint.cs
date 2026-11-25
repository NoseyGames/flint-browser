using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Text;
using System.Windows.Forms;

[assembly: AssemblyTitle("Flint")]
[assembly: AssemblyProduct("Flint Browser")]

internal static class Flint
{
    // ProcessStartInfo on the system .NET Framework takes one Windows command line.
    private static string Quote(string value)
    {
        var result = new StringBuilder("\"");
        int slashes = 0;
        foreach (char c in value)
        {
            if (c == '\\') { slashes++; continue; }
            result.Append('\\', c == '"' ? slashes * 2 + 1 : slashes);
            result.Append(c);
            slashes = 0;
        }
        return result.Append('\\', slashes * 2).Append('"').ToString();
    }

    private static void InitializeProfile(string script, string profile)
    {
        if (File.Exists(Path.Combine(profile, "Local State"))) return;
        var start = new ProcessStartInfo {
            FileName = Path.Combine(Environment.SystemDirectory, @"WindowsPowerShell\v1.0\powershell.exe"),
            Arguments = "-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File " + Quote(script) + " -UserDataDir " + Quote(profile),
            UseShellExecute = false, CreateNoWindow = true, RedirectStandardError = true
        };
        using (var setup = Process.Start(start))
        {
            string message = setup.StandardError.ReadToEnd();
            setup.WaitForExit();
            if (setup.ExitCode != 0) throw new InvalidOperationException("Could not initialize the Flint profile.\n\n" + message.Trim());
        }
    }

    [STAThread]
    private static int Main(string[] args)
    {
        try
        {
            string root = AppDomain.CurrentDomain.BaseDirectory;
            string windows = Path.Combine(root, @"flint\windows");
            string extension = Path.Combine(root, @"flint\extension");
            string version;
            using (var reader = new StreamReader(typeof(Flint).Assembly.GetManifestResourceStream("Flint.Engine")))
                version = reader.ReadToEnd().Trim();
            string browser = Path.Combine(windows, "runtime", version, "chrome.exe");
            if (!File.Exists(browser) || !File.Exists(Path.Combine(extension, "manifest.json")))
                throw new FileNotFoundException("Keep Flint.exe alongside its flint folder. Run Build-Flint.ps1 to restore the runtime.");
            if (extension.Contains(",")) throw new InvalidOperationException("Chromium separates extension paths with commas. Move Flint to a folder whose path contains no comma.");

            string profile = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Flint", "User Data");
            var flags = new List<string> { "--user-data-dir=" + profile, "--load-extension=" + extension, "--no-default-browser-check" };
            foreach (string arg in args)
            {
                Uri url;
                if (!Uri.TryCreate(arg, UriKind.Absolute, out url) || (url.Scheme != Uri.UriSchemeHttps && url.Scheme != Uri.UriSchemeHttp))
                    throw new ArgumentException("Flint.exe accepts web addresses beginning with https:// or http://.");
                flags.Add(url.AbsoluteUri);
            }
            InitializeProfile(Path.Combine(windows, "Initialize-Profile.ps1"), profile);
            using (Process.Start(new ProcessStartInfo(browser, String.Join(" ", flags.ConvertAll(Quote))) { UseShellExecute = false })) { }
            return 0;
        }
        catch (Exception error)
        {
            MessageBox.Show(error.Message, "Flint", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
    }
}
