using System.Diagnostics;
using System.Globalization;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Security.AccessControl;
using System.Security.Principal;
using System.Text;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;

namespace SSDInstaller;

internal static class Program
{
    [STAThread]
    static void Main()
    {
        ApplicationConfiguration.Initialize();
        if (!Environment.Is64BitOperatingSystem || RuntimeInformation.OSArchitecture != Architecture.X64)
        {
            MessageBox.Show(Lang.T("Versi ini memerlukan Windows 10/11 x64 (Intel/AMD).", "This version requires Windows 10/11 x64 (Intel/AMD)."), "SSD Installer");
            return;
        }
        string sessionDir;
        try { sessionDir = Workspace.CreateSession(); }
        catch (Exception ex)
        {
            MessageBox.Show(Lang.T("Folder kerja aman tidak dapat disiapkan: ", "Cannot prepare the secure work folder: ") + ex.Message, "SSD Installer", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return;
        }
        Application.Run(new MainForm(sessionDir));
    }
}

internal static class Lang
{
    static readonly string settings = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "SSDInstaller", "language.txt");
    public static bool En { get; private set; } = Load();
    static bool Load()
    {
        try { if (File.Exists(settings)) return File.ReadAllText(settings).Trim() == "en"; }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException) { }
        return CultureInfo.CurrentUICulture.TwoLetterISOLanguageName != "id" && CultureInfo.CurrentCulture.TwoLetterISOLanguageName != "id";
    }
    public static void Set(bool en)
    {
        En = en;
        try { Directory.CreateDirectory(Path.GetDirectoryName(settings)!); File.WriteAllText(settings, en ? "en" : "id"); }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException) { }
    }
    public static string T(string id, string en) => En ? en : id;
}

// The engine runs elevated, so its script and request files live where only Administrators and SYSTEM can write.
internal static class Workspace
{
    public static string CreateSession()
    {
        var root = Secure(new DirectoryInfo(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData), "SSDInstaller")));
        var sessions = Secure(new DirectoryInfo(Path.Combine(root.FullName, "Sessions")));
        var session = Path.Combine(sessions.FullName, DateTime.Now.ToString("yyyyMMdd-HHmmss") + "-" + Guid.NewGuid().ToString("N")[..8]);
        Directory.CreateDirectory(session);
        return session;
    }
    static DirectoryInfo Secure(DirectoryInfo dir)
    {
        var admins = new SecurityIdentifier(WellKnownSidType.BuiltinAdministratorsSid, null);
        const InheritanceFlags all = InheritanceFlags.ContainerInherit | InheritanceFlags.ObjectInherit;
        var acl = new DirectorySecurity();
        acl.SetOwner(admins);
        acl.SetAccessRuleProtection(true, false);
        acl.AddAccessRule(new FileSystemAccessRule(admins, FileSystemRights.FullControl, all, PropagationFlags.None, AccessControlType.Allow));
        acl.AddAccessRule(new FileSystemAccessRule(new SecurityIdentifier(WellKnownSidType.LocalSystemSid, null), FileSystemRights.FullControl, all, PropagationFlags.None, AccessControlType.Allow));
        acl.AddAccessRule(new FileSystemAccessRule(new SecurityIdentifier(WellKnownSidType.BuiltinUsersSid, null), FileSystemRights.ReadAndExecute, all, PropagationFlags.None, AccessControlType.Allow));
        dir.Refresh();
        if (!dir.Exists) { dir.Create(acl); return dir; }
        if ((dir.Attributes & FileAttributes.ReparsePoint) != 0) throw new IOException(Lang.T("Folder kerja berupa junction/symlink: ", "The work folder is a junction/symlink: ") + dir.FullName);
        dir.SetAccessControl(acl);
        return dir;
    }
}

internal sealed class Choice(JsonObject data, string label)
{
    public JsonObject Data { get; } = data;
    public override string ToString() => label;
}

internal sealed class MainForm : Form
{
    readonly TextBox iso = new() { ReadOnly = true, Dock = DockStyle.Fill };
    readonly TextBox drivers = new() { ReadOnly = true, Dock = DockStyle.Fill };
    readonly TextBox localAccount = new() { Dock = DockStyle.Fill, MaxLength = 20 };
    readonly ComboBox editions = new() { DropDownStyle = ComboBoxStyle.DropDownList, Dock = DockStyle.Fill };
    readonly ComboBox disks = new() { DropDownStyle = ComboBoxStyle.DropDownList, Dock = DockStyle.Fill, DropDownWidth = 900 };
    readonly ComboBox mode = new() { DropDownStyle = ComboBoxStyle.DropDownList, Dock = DockStyle.Fill };
    readonly ComboBox language = new() { DropDownStyle = ComboBoxStyle.DropDownList, Width = 160, Anchor = AnchorStyles.Top | AnchorStyles.Right };
    readonly TextBox planText = new() { Multiline = true, ReadOnly = true, ScrollBars = ScrollBars.Vertical, Dock = DockStyle.Fill, BackColor = Color.White };
    readonly TextBox logText = new() { Multiline = true, ReadOnly = true, ScrollBars = ScrollBars.Both, WordWrap = false, Dock = DockStyle.Fill, Font = new Font("Consolas", 9) };
    readonly Label status = new() { AutoSize = true, Dock = DockStyle.Fill };
    readonly ProgressBar progress = new() { Dock = DockStyle.Fill, Height = 8 };
    static readonly Color installOn = Color.FromArgb(26, 92, 195), installOff = Color.FromArgb(222, 226, 232);
    readonly Button install = new() { AutoSize = true, Enabled = false, BackColor = installOff, ForeColor = Color.White, FlatStyle = FlatStyle.Flat };
    readonly List<Control> inputs = [];
    readonly List<Action> texts = [];
    readonly string sessionDir;
    readonly string enginePath;
    readonly string logPath;
    readonly object logLock = new();
    static readonly Regex percent = new(@"(\d{1,3}(?:\.\d+)?)%");
    string phase = "";
    JsonObject? plan;
    bool busy;

    [DllImport("kernel32.dll")] static extern uint SetThreadExecutionState(uint flags);
    const uint EsContinuous = 0x80000000, EsSystemRequired = 0x00000001;

    static string L(string id, string en) => Lang.T(id, en);
    T Txt<T>(T control, string id, string en) where T : Control { texts.Add(() => control.Text = L(id, en)); return control; }

    public MainForm(string sessionDir)
    {
        var version = typeof(Program).Assembly.GetName().Version!;
        texts.Add(() => Text = $"SSD Installer {version.Major}.{version.Minor} • {L("Pratinjau", "Preview")}");
        StartPosition = FormStartPosition.CenterScreen;
        Size = new Size(1040, 900);
        MinimumSize = new Size(860, 740);
        Font = new Font("Segoe UI", 10);
        BackColor = Color.FromArgb(245, 247, 251);
        AutoScaleMode = AutoScaleMode.Dpi;
        try { Icon = Icon.ExtractAssociatedIcon(Environment.ProcessPath!); } catch (ArgumentException) { }
        this.sessionDir = sessionDir;
        enginePath = Path.Combine(sessionDir, "Engine.ps1");
        logPath = Path.Combine(sessionDir, "session.log");
        using (var resource = Assembly.GetExecutingAssembly().GetManifestResourceStream("SSDInstaller.Engine.ps1")!)
        using (var file = new FileStream(enginePath, FileMode.CreateNew, FileAccess.Write)) resource.CopyTo(file);

        var root = new TableLayoutPanel { Dock = DockStyle.Fill, Padding = new Padding(24), ColumnCount = 1, RowCount = 9 };
        for (var n = 0; n < 9; n++) root.RowStyles.Add(new RowStyle(n == 5 ? SizeType.Percent : SizeType.AutoSize, n == 5 ? 100 : 0));
        Controls.Add(root);
        var header = new TableLayoutPanel { AutoSize = true, Dock = DockStyle.Fill, ColumnCount = 2, Margin = new Padding(0) };
        header.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100)); header.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
        header.Controls.Add(Txt(new Label { Font = new Font("Segoe UI", 23, FontStyle.Bold), AutoSize = true, Margin = new Padding(0, 0, 0, 8) }, "Windows langsung ke SSD", "Windows straight to SSD"), 0, 0);
        language.Items.AddRange(["Bahasa Indonesia", "English"]);
        language.SelectedIndex = Lang.En ? 1 : 0;
        header.Controls.Add(language, 1, 0);
        root.Controls.Add(header, 0, 0);
        root.Controls.Add(Txt(new Label { AutoSize = true, Margin = new Padding(0, 0, 0, 12) }, "ISO → SSD lewat USB → pasang SSD di dalam PC/laptop → boot Windows", "ISO → SSD over USB → fit the SSD inside the PC/laptop → boot Windows"), 0, 1);
        root.Controls.Add(Txt(new Label { AutoSize = true, ForeColor = Color.FromArgb(135, 65, 10), Margin = new Padding(0, 0, 0, 14) },
            "PRATINJAU • Pemasangan menghapus seluruh isi SSD pilihan. Gunakan SSD kosong/cadangan.\nVersi ini mendukung ISO Windows 10/11 x64, bukan Windows portable USB.",
            "PREVIEW • Installing erases everything on the selected SSD. Use an empty or spare SSD.\nThis version supports Windows 10/11 x64 ISOs, not portable Windows on USB."), 0, 2);

        var fields = new TableLayoutPanel { AutoSize = true, Dock = DockStyle.Fill, ColumnCount = 3, RowCount = 6 };
        fields.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 175));
        fields.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        fields.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 160));
        void Row(int n, string id, string en, Control value, Control? action)
        {
            fields.Controls.Add(Txt(new Label { AutoSize = true, Anchor = AnchorStyles.Left }, id, en), 0, n);
            value.Margin = new Padding(3, 7, 8, 7); fields.Controls.Add(value, 1, n); inputs.Add(value);
            if (action != null) { fields.Controls.Add(action, 2, n); inputs.Add(action); }
        }
        var browse = Txt(new Button { Dock = DockStyle.Fill }, "Pilih ISO…", "Select ISO…");
        browse.Click += async (_, _) => {
            using var d = new OpenFileDialog { Filter = L("ISO Windows", "Windows ISO") + " (*.iso)|*.iso", CheckFileExists = true };
            if (d.ShowDialog() != DialogResult.OK) return;
            iso.Text = d.FileName; editions.Items.Clear(); InvalidatePlan();
            await Busy(async () => {
                var data = await Run(new JsonObject { ["action"] = "Inspect", ["iso"] = iso.Text });
                foreach (var item in data["images"]!.AsArray()) {
                    var obj = item!.AsObject();
                    editions.Items.Add(new Choice(obj, $"{obj["index"]} • {obj["name"]} • {obj["version"]} ({obj["architecture"]})"));
                }
                if (editions.Items.Count > 0) editions.SelectedIndex = 0;
                status.Text = L("ISO terbaca. Pilih edisi, SSD, dan mode boot komputer tujuan.", "ISO read. Choose the edition, SSD and the target computer's boot mode.");
            });
        };
        var refresh = Txt(new Button { Dock = DockStyle.Fill }, "Cari SSD USB", "Find USB SSD");
        refresh.Click += async (_, _) => await RefreshDisks();
        var driverButtons = new FlowLayoutPanel { Dock = DockStyle.Fill, AutoSize = true };
        var driverBrowse = Txt(new Button { AutoSize = true }, "Pilih…", "Browse…");
        var clearDrivers = new Button { Text = "×", Width = 35 };
        driverButtons.Controls.AddRange([driverBrowse, clearDrivers]);
        driverBrowse.Click += (_, _) => { using var d = new FolderBrowserDialog { Description = L("Folder driver storage x64 dari produsen (berisi .inf)", "Vendor x64 storage driver folder (containing .inf)") }; if (d.ShowDialog() == DialogResult.OK) drivers.Text = d.SelectedPath; };
        clearDrivers.Click += (_, _) => drivers.Text = "";
        mode.Items.AddRange(["UEFI / GPT — Windows 10 / 11", "Legacy BIOS / MBR — Windows 10"]); mode.SelectedIndex = 0;
        Row(0, "1. ISO Windows", "1. Windows ISO", iso, browse);
        Row(1, "Edisi Windows", "Windows edition", editions, null);
        Row(2, "SSD tujuan (USB)", "Target SSD (USB)", disks, refresh);
        Row(3, "Mode boot tujuan", "Target boot mode", mode, null);
        Row(4, "Driver .inf (opsional)", "Driver .inf (optional)", drivers, driverButtons);
        Row(5, "Akun lokal (opsional)", "Local account (optional)", localAccount, null);
        root.Controls.Add(fields, 0, 3);
        root.Controls.Add(Txt(new Label { AutoSize = true, Margin = new Padding(0, 8, 0, 12) },
            "Pilih mode sesuai firmware komputer tujuan. Driver Intel RST/VMD/RAID mungkin perlu ditambahkan.\nAkun lokal: isi nama (tanpa spasi) untuk membuat akun administrator tanpa password dan melewati akun Microsoft.",
            "Choose the mode that matches the target computer's firmware. Intel RST/VMD/RAID drivers may be needed.\nLocal account: enter a name (no spaces) to create a passwordless administrator and skip the Microsoft account."), 0, 4);

        var tabs = new TabControl { Dock = DockStyle.Fill, MinimumSize = new Size(200, 180) };
        var p = Txt(new TabPage(), "Rencana pemasangan", "Install plan"); p.Controls.Add(planText); tabs.TabPages.Add(p);
        var l = Txt(new TabPage(), "Log proses", "Process log"); l.Controls.Add(logText); tabs.TabPages.Add(l);
        root.Controls.Add(tabs, 0, 5);
        var actions = new FlowLayoutPanel { AutoSize = true, Dock = DockStyle.Fill, Margin = new Padding(0, 12, 0, 10) };
        var check = Txt(new Button { AutoSize = true }, "2. Periksa tanpa format", "2. Check without formatting");
        Txt(install, "3. Pasang Windows…", "3. Install Windows…");
        var openLogs = Txt(new Button { AutoSize = true }, "Buka folder log", "Open log folder");
        check.Click += async (_, _) => await Busy(async () => {
            plan = null; install.Enabled = false;
            plan = await Run(Request("Preflight"));
            planText.Text = Summary(plan);
            status.Text = L("Pemeriksaan selesai. Baca rencana sebelum melanjutkan.", "Check complete. Read the plan before continuing.");
            tabs.SelectedTab = p;
        });
        install.Click += async (_, _) => {
            if (plan == null) return;
            var expected = L($"HAPUS DISK {plan["disk"]!["number"]}", $"ERASE DISK {plan["disk"]!["number"]}");
            using var confirm = new ConfirmForm(Summary(plan), expected);
            if (confirm.ShowDialog(this) != DialogResult.OK) return;
            var request = Request("Install"); request["plan"] = plan.DeepClone(); request["confirmation"] = expected;
            plan = null;
            await Busy(async () => {
                tabs.SelectedTab = l;
                var result = await Run(request);
                planText.Text = Summary(result);
                tabs.SelectedTab = p;
                progress.Value = 100;
                status.Text = L("Selesai. Berkas Windows dan boot telah diverifikasi.", "Done. Windows and boot files were verified.");
                MessageBox.Show(this, planText.Text, L("Penyalinan selesai", "Copy complete"), MessageBoxButtons.OK, MessageBoxIcon.Information);
            });
        };
        // Flat buttons keep their BackColor when disabled; show the locked state as gray.
        install.EnabledChanged += (_, _) => install.BackColor = install.Enabled ? installOn : installOff;
        openLogs.Click += (_, _) => Process.Start(new ProcessStartInfo("explorer.exe", sessionDir) { UseShellExecute = true });
        actions.Controls.AddRange([check, install, openLogs]); inputs.Add(check);
        root.Controls.Add(actions, 0, 6); root.Controls.Add(progress, 0, 7); root.Controls.Add(status, 0, 8);
        editions.SelectedIndexChanged += (_, _) => InvalidatePlan();
        disks.SelectedIndexChanged += (_, _) => InvalidatePlan();
        mode.SelectedIndexChanged += (_, _) => InvalidatePlan();
        drivers.TextChanged += (_, _) => InvalidatePlan();
        localAccount.TextChanged += (_, _) => InvalidatePlan();
        language.SelectedIndexChanged += (_, _) => { Lang.Set(language.SelectedIndex == 1); ApplyTexts(); };
        FormClosing += (_, e) => { if (busy) { e.Cancel = true; MessageBox.Show(this, L("Proses masih berjalan. Jangan tutup aplikasi atau cabut SSD.", "A process is still running. Do not close the app or unplug the SSD.")); } };
        Shown += async (_, _) => await RefreshDisks();
        ApplyTexts();
    }

    void ApplyTexts()
    {
        foreach (var apply in texts) apply();
        localAccount.PlaceholderText = L("kosongkan = akun dibuat saat setup Windows", "leave empty = create the account during Windows setup");
        if (plan == null) planText.Text = L("Klik Periksa untuk melihat identitas SSD dan rencana partisi. Pemeriksaan tidak memformat SSD.", "Click Check to see the SSD identity and partition plan. Checking does not format the SSD.");
        if (!busy) status.Text = L("Pilih ISO untuk memulai.", "Select an ISO to start.");
    }
    // Engine here-strings may use LF only; WinForms TextBox needs CRLF to break lines.
    static string Summary(JsonObject data) => data["summary"]!.GetValue<string>().ReplaceLineEndings("\r\n");
    void InvalidatePlan() { plan = null; install.Enabled = false; planText.Text = L("Pilihan berubah. Jalankan Periksa tanpa format untuk membuat rencana baru.", "Selection changed. Run Check without formatting to build a new plan."); }
    JsonObject Request(string action)
    {
        if (editions.SelectedItem is not Choice edition || disks.SelectedItem is not Choice disk) throw new InvalidOperationException(L("Pilih ISO, edisi, dan SSD USB terlebih dahulu.", "Select an ISO, edition and USB SSD first."));
        return new JsonObject { ["action"] = action, ["iso"] = iso.Text, ["index"] = edition.Data["index"]!.DeepClone(), ["disk"] = disk.Data.DeepClone(), ["mode"] = mode.SelectedIndex == 0 ? "UEFI" : "BIOS", ["drivers"] = drivers.Text, ["localAccount"] = localAccount.Text.Trim() };
    }
    async Task RefreshDisks() => await Busy(async () => {
        InvalidatePlan(); disks.Items.Clear();
        var data = await Run(new JsonObject { ["action"] = "List" });
        foreach (var item in data["disks"]!.AsArray()) {
            var d = item!.AsObject();
            disks.Items.Add(new Choice(d, $"Disk {d["number"]} • {d["name"]} • {d["sizeGiB"]} GiB • SN {d["serial"]} • {d["partitionStyle"]}"));
        }
        // Never preselect a target disk.
        status.Text = disks.Items.Count == 0
            ? L("Tidak ada SSD USB yang memenuhi pemeriksaan dasar. Lihat log.", "No USB SSD passed the basic checks. See the log.")
            : L("Pilih SSD berdasarkan kapasitas dan nomor seri; SSD tidak dipilih otomatis.", "Pick the SSD by capacity and serial number; it is never selected automatically.");
    });
    async Task Busy(Func<Task> work)
    {
        if (busy) return;
        busy = true; foreach (var c in inputs) c.Enabled = false; install.Enabled = false; language.Enabled = false;
        // Keep Windows awake while the engine runs; sleeping mid-install would leave a half-written SSD.
        SetThreadExecutionState(EsContinuous | EsSystemRequired);
        phase = ""; progress.Style = ProgressBarStyle.Marquee; status.Text = L("Memproses… lihat tab Log proses.", "Working… see the Process log tab.");
        try { await work(); }
        catch (Exception ex)
        {
            plan = null; status.Text = L("Proses dihentikan: ", "Stopped: ") + ex.Message; Log("GAGAL/FAILED: " + ex);
            MessageBox.Show(this, ex.Message + L("\n\nLihat log untuk detail. Jika format sudah dimulai, data lama tidak dipulihkan otomatis.", "\n\nSee the log for details. If formatting already started, old data is not restored automatically."), L("Proses tidak selesai", "Process not completed"), MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
        finally
        {
            SetThreadExecutionState(EsContinuous);
            busy = false; foreach (var c in inputs) c.Enabled = true; install.Enabled = plan != null; language.Enabled = true;
            if (progress.Value != 100) progress.Value = 0;
            progress.Style = ProgressBarStyle.Blocks;
        }
    }
    void Log(string line)
    {
        if (string.IsNullOrWhiteSpace(line)) return;
        lock (logLock) File.AppendAllText(logPath, $"{DateTime.Now:HH:mm:ss} {line}{Environment.NewLine}", Encoding.UTF8);
        if (!IsHandleCreated || IsDisposed) return;
        BeginInvoke(() => {
            // DISM draws "[====  42.0%  ====]" bars: drive the progress bar instead of flooding the log view.
            var match = line.TrimStart().StartsWith('[') ? percent.Match(line) : Match.Empty;
            if (match.Success && double.TryParse(match.Groups[1].Value, NumberStyles.Float, CultureInfo.InvariantCulture, out var pct))
            {
                progress.Style = ProgressBarStyle.Continuous;
                progress.Value = (int)Math.Clamp(pct, 0, 100);
                status.Text = $"{phase}… {pct:0}%";
                return;
            }
            if (line.EndsWith("...")) { phase = line[..^3]; status.Text = phase + "…"; }
            logText.AppendText(line + Environment.NewLine);
        });
    }
    async Task<JsonObject> Run(JsonObject request)
    {
        var id = Guid.NewGuid().ToString("N");
        var req = Path.Combine(sessionDir, id + ".request.json");
        var res = Path.Combine(sessionDir, id + ".result.json");
        request["appPath"] = Environment.ProcessPath;
        request["lang"] = Lang.En ? "en" : "id";
        await File.WriteAllTextAsync(req, request.ToJsonString(), new UTF8Encoding(false));
        var start = new ProcessStartInfo(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows), "System32", "WindowsPowerShell", "v1.0", "powershell.exe")) {
            UseShellExecute = false, CreateNoWindow = true, RedirectStandardOutput = true, RedirectStandardError = true,
            StandardOutputEncoding = Encoding.UTF8, StandardErrorEncoding = Encoding.UTF8
        };
        foreach (var arg in new[] { "-NoLogo", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", enginePath, "-RequestPath", req, "-ResultPath", res }) start.ArgumentList.Add(arg);
        using var process = new Process { StartInfo = start };
        process.Start();
        async Task Pump(StreamReader reader) { while (await reader.ReadLineAsync() is { } line) Log(line); }
        await Task.WhenAll(Pump(process.StandardOutput), Pump(process.StandardError), process.WaitForExitAsync());
        if (!File.Exists(res)) throw new InvalidOperationException(L($"Mesin pemasangan berhenti (kode {process.ExitCode}). Periksa log; kebijakan Windows mungkin memblokir PowerShell.", $"The install engine stopped (code {process.ExitCode}). Check the log; a Windows policy may be blocking PowerShell."));
        var response = JsonNode.Parse(await File.ReadAllTextAsync(res))!.AsObject();
        if (process.ExitCode != 0 || response["ok"]?.GetValue<bool>() != true) throw new InvalidOperationException(response["error"]?.GetValue<string>() ?? L("Pemasangan gagal.", "Installation failed."));
        return response["data"]!.AsObject();
    }
}

internal sealed class ConfirmForm : Form
{
    public ConfirmForm(string summary, string phrase)
    {
        Text = Lang.T("Konfirmasi penghapusan SSD", "Confirm SSD erase"); Size = new Size(750, 620); MinimumSize = Size;
        StartPosition = FormStartPosition.CenterParent; Font = new Font("Segoe UI", 10);
        var root = new TableLayoutPanel { Dock = DockStyle.Fill, Padding = new Padding(18), RowCount = 5, ColumnCount = 1 };
        root.RowStyles.Add(new RowStyle(SizeType.Percent, 100)); for (var i = 1; i < 5; i++) root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        root.Controls.Add(new TextBox { Text = summary, Multiline = true, ReadOnly = true, ScrollBars = ScrollBars.Vertical, Dock = DockStyle.Fill }, 0, 0);
        var consent = new CheckBox { Text = Lang.T("Saya sudah mencadangkan data dan mengizinkan seluruh SSD ini dihapus.", "I have backed up my data and allow this whole SSD to be erased."), AutoSize = true, Margin = new Padding(3, 15, 3, 10) };
        root.Controls.Add(consent, 0, 1);
        root.Controls.Add(new Label { Text = Lang.T("Ketik persis: ", "Type exactly: ") + phrase, AutoSize = true }, 0, 2);
        var text = new TextBox { Dock = DockStyle.Fill }; root.Controls.Add(text, 0, 3);
        var buttons = new FlowLayoutPanel { AutoSize = true, Dock = DockStyle.Fill };
        var yes = new Button { Text = Lang.T("Hapus & pasang", "Erase & install"), AutoSize = true, Enabled = false, DialogResult = DialogResult.OK };
        var no = new Button { Text = Lang.T("Batal", "Cancel"), AutoSize = true, DialogResult = DialogResult.Cancel };
        void Check() => yes.Enabled = consent.Checked && text.Text == phrase;
        text.TextChanged += (_, _) => Check(); consent.CheckedChanged += (_, _) => Check();
        buttons.Controls.AddRange([no, yes]); root.Controls.Add(buttons, 0, 4); Controls.Add(root); CancelButton = no;
    }
}
