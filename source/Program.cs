using System.Diagnostics;
using System.Reflection;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace SSDInstaller;

internal static class Program
{
    [STAThread]
    static void Main()
    {
        ApplicationConfiguration.Initialize();
        if (!Environment.Is64BitOperatingSystem || System.Runtime.InteropServices.RuntimeInformation.OSArchitecture != System.Runtime.InteropServices.Architecture.X64)
        {
            MessageBox.Show("Versi ini memerlukan Windows 10/11 x64 (Intel/AMD).", "SSD Installer");
            return;
        }
        Application.Run(new MainForm());
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
    readonly ComboBox editions = new() { DropDownStyle = ComboBoxStyle.DropDownList, Dock = DockStyle.Fill };
    readonly ComboBox disks = new() { DropDownStyle = ComboBoxStyle.DropDownList, Dock = DockStyle.Fill, DropDownWidth = 900 };
    readonly ComboBox mode = new() { DropDownStyle = ComboBoxStyle.DropDownList, Dock = DockStyle.Fill };
    readonly TextBox planText = new() { Multiline = true, ReadOnly = true, ScrollBars = ScrollBars.Vertical, Dock = DockStyle.Fill, BackColor = Color.White };
    readonly TextBox logText = new() { Multiline = true, ReadOnly = true, ScrollBars = ScrollBars.Both, WordWrap = false, Dock = DockStyle.Fill, Font = new Font("Consolas", 9) };
    readonly Label status = new() { AutoSize = true, Text = "Pilih ISO untuk memulai.", Dock = DockStyle.Fill };
    readonly ProgressBar progress = new() { Dock = DockStyle.Fill, Height = 8 };
    static readonly Color installOn = Color.FromArgb(26, 92, 195), installOff = Color.FromArgb(222, 226, 232);
    readonly Button install = new() { Text = "3. Pasang Windows…", AutoSize = true, Enabled = false, BackColor = installOff, ForeColor = Color.White, FlatStyle = FlatStyle.Flat };
    readonly List<Control> inputs = [];
    readonly string sessionDir;
    readonly string enginePath;
    readonly string logPath;
    readonly object logLock = new();
    JsonObject? plan;
    bool busy;

    public MainForm()
    {
        Text = "SSD Installer • Pratinjau 0.1";
        StartPosition = FormStartPosition.CenterScreen;
        Size = new Size(1040, 850);
        MinimumSize = new Size(860, 700);
        Font = new Font("Segoe UI", 10);
        BackColor = Color.FromArgb(245, 247, 251);
        AutoScaleMode = AutoScaleMode.Dpi;
        sessionDir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "SSDInstaller", "Sessions", DateTime.Now.ToString("yyyyMMdd-HHmmss") + "-" + Guid.NewGuid().ToString("N")[..8]);
        Directory.CreateDirectory(sessionDir);
        enginePath = Path.Combine(sessionDir, "Engine.ps1");
        logPath = Path.Combine(sessionDir, "session.log");
        using (var resource = Assembly.GetExecutingAssembly().GetManifestResourceStream("SSDInstaller.Engine.ps1")!)
        using (var file = File.Create(enginePath)) resource.CopyTo(file);

        var root = new TableLayoutPanel { Dock = DockStyle.Fill, Padding = new Padding(24), ColumnCount = 1, RowCount = 9 };
        for (var n = 0; n < 9; n++) root.RowStyles.Add(new RowStyle(n == 5 ? SizeType.Percent : SizeType.AutoSize, n == 5 ? 100 : 0));
        Controls.Add(root);
        root.Controls.Add(new Label { Text = "Windows langsung ke SSD", Font = new Font("Segoe UI", 23, FontStyle.Bold), AutoSize = true, Margin = new Padding(0, 0, 0, 8) }, 0, 0);
        root.Controls.Add(new Label { Text = "ISO → SSD lewat USB → pasang SSD di dalam PC/laptop → boot Windows", AutoSize = true, Margin = new Padding(0, 0, 0, 12) }, 0, 1);
        root.Controls.Add(new Label { Text = "PRATINJAU • Belum diuji boot pada SSD fisik. Pemasangan menghapus seluruh isi SSD pilihan.\nGunakan SSD kosong/cadangan. Versi ini mendukung ISO Windows 10/11 x64, bukan Windows portable USB.", AutoSize = true, ForeColor = Color.FromArgb(135, 65, 10), Margin = new Padding(0, 0, 0, 14) }, 0, 2);

        var fields = new TableLayoutPanel { AutoSize = true, Dock = DockStyle.Fill, ColumnCount = 3, RowCount = 5 };
        fields.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 155));
        fields.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        fields.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 160));
        void Row(int n, string title, Control value, Control? action)
        {
            fields.Controls.Add(new Label { Text = title, AutoSize = true, Anchor = AnchorStyles.Left }, 0, n);
            value.Margin = new Padding(3, 7, 8, 7); fields.Controls.Add(value, 1, n); inputs.Add(value);
            if (action != null) { fields.Controls.Add(action, 2, n); inputs.Add(action); }
        }
        var browse = new Button { Text = "Pilih ISO…", Dock = DockStyle.Fill };
        browse.Click += async (_, _) => {
            using var d = new OpenFileDialog { Filter = "ISO Windows (*.iso)|*.iso", CheckFileExists = true };
            if (d.ShowDialog() != DialogResult.OK) return;
            iso.Text = d.FileName; editions.Items.Clear(); InvalidatePlan();
            await Busy(async () => {
                var data = await Run(new JsonObject { ["action"] = "Inspect", ["iso"] = iso.Text });
                foreach (var item in data["images"]!.AsArray()) {
                    var obj = item!.AsObject();
                    editions.Items.Add(new Choice(obj, $"{obj["index"]} • {obj["name"]} • {obj["version"]} ({obj["architecture"]})"));
                }
                if (editions.Items.Count > 0) editions.SelectedIndex = 0;
                status.Text = "ISO terbaca. Pilih edisi, SSD, dan mode boot komputer tujuan.";
            });
        };
        var refresh = new Button { Text = "Cari SSD USB", Dock = DockStyle.Fill };
        refresh.Click += async (_, _) => await RefreshDisks();
        var driverButtons = new FlowLayoutPanel { Dock = DockStyle.Fill, AutoSize = true };
        var driverBrowse = new Button { Text = "Pilih…", AutoSize = true };
        var clearDrivers = new Button { Text = "×", Width = 35 };
        driverButtons.Controls.AddRange([driverBrowse, clearDrivers]);
        driverBrowse.Click += (_, _) => { using var d = new FolderBrowserDialog { Description = "Folder driver storage x64 dari produsen (berisi .inf)" }; if (d.ShowDialog() == DialogResult.OK) drivers.Text = d.SelectedPath; };
        clearDrivers.Click += (_, _) => drivers.Text = "";
        mode.Items.AddRange(["UEFI / GPT — Windows 10 atau 11", "Legacy BIOS / MBR — Windows 10"]); mode.SelectedIndex = 0;
        Row(0, "1. ISO Windows", iso, browse);
        Row(1, "Edisi Windows", editions, null);
        Row(2, "SSD tujuan (USB)", disks, refresh);
        Row(3, "Mode boot tujuan", mode, null);
        Row(4, "Driver .inf (opsional)", drivers, driverButtons);
        root.Controls.Add(fields, 0, 3);
        root.Controls.Add(new Label { Text = "Pilih mode sesuai firmware komputer tujuan. Driver Intel RST/VMD/RAID mungkin perlu ditambahkan.\nWindows 11 memerlukan perangkat yang memenuhi persyaratannya. Gunakan ISO resmi dan terbaru.", AutoSize = true, Margin = new Padding(0, 8, 0, 12) }, 0, 4);

        var tabs = new TabControl { Dock = DockStyle.Fill, MinimumSize = new Size(200, 180) };
        var p = new TabPage("Rencana pemasangan"); p.Controls.Add(planText); tabs.TabPages.Add(p);
        var l = new TabPage("Log proses"); l.Controls.Add(logText); tabs.TabPages.Add(l);
        planText.Text = "Klik Periksa untuk melihat identitas SSD dan rencana partisi. Pemeriksaan tidak memformat SSD.";
        root.Controls.Add(tabs, 0, 5);
        var actions = new FlowLayoutPanel { AutoSize = true, Dock = DockStyle.Fill, Margin = new Padding(0, 12, 0, 10) };
        var check = new Button { Text = "2. Periksa tanpa format", AutoSize = true };
        var openLogs = new Button { Text = "Buka folder log", AutoSize = true };
        check.Click += async (_, _) => await Busy(async () => {
            plan = null; install.Enabled = false;
            plan = await Run(Request("Preflight"));
            planText.Text = Summary(plan);
            status.Text = "Pemeriksaan selesai. Baca rencana sebelum melanjutkan.";
            tabs.SelectedTab = p;
        });
        install.Click += async (_, _) => {
            if (plan == null) return;
            var expected = $"HAPUS DISK {plan["disk"]!["number"]}";
            using var confirm = new ConfirmForm(Summary(plan), expected);
            if (confirm.ShowDialog(this) != DialogResult.OK) return;
            var request = Request("Install"); request["plan"] = plan.DeepClone(); request["confirmation"] = expected;
            plan = null;
            await Busy(async () => {
                tabs.SelectedTab = l;
                var result = await Run(request);
                planText.Text = Summary(result);
                tabs.SelectedTab = p;
                status.Text = "Berkas Windows dan boot telah diverifikasi. Pengujian boot fisik masih diperlukan.";
                MessageBox.Show(this, planText.Text, "Penyalinan selesai", MessageBoxButtons.OK, MessageBoxIcon.Information);
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
        FormClosing += (_, e) => { if (busy) { e.Cancel = true; MessageBox.Show(this, "Proses masih berjalan. Jangan tutup aplikasi atau cabut SSD."); } };
        Shown += async (_, _) => await RefreshDisks();
    }

    // Engine here-strings may use LF only; WinForms TextBox needs CRLF to break lines.
    static string Summary(JsonObject data) => data["summary"]!.GetValue<string>().ReplaceLineEndings("\r\n");
    void InvalidatePlan() { plan = null; install.Enabled = false; planText.Text = "Pilihan berubah. Jalankan Periksa tanpa format untuk membuat rencana baru."; }
    JsonObject Request(string action)
    {
        if (editions.SelectedItem is not Choice edition || disks.SelectedItem is not Choice disk) throw new InvalidOperationException("Pilih ISO, edisi, dan SSD USB terlebih dahulu.");
        return new JsonObject { ["action"] = action, ["iso"] = iso.Text, ["index"] = edition.Data["index"]!.DeepClone(), ["disk"] = disk.Data.DeepClone(), ["mode"] = mode.SelectedIndex == 0 ? "UEFI" : "BIOS", ["drivers"] = drivers.Text };
    }
    async Task RefreshDisks() => await Busy(async () => {
        InvalidatePlan(); disks.Items.Clear();
        var data = await Run(new JsonObject { ["action"] = "List" });
        foreach (var item in data["disks"]!.AsArray()) {
            var d = item!.AsObject();
            disks.Items.Add(new Choice(d, $"Disk {d["number"]} • {d["name"]} • {d["sizeGiB"]} GiB • SN {d["serial"]} • {d["partitionStyle"]}"));
        }
        // Never preselect a target disk.
        status.Text = disks.Items.Count == 0 ? "Tidak ada SSD USB yang memenuhi pemeriksaan dasar. Lihat log." : "Pilih SSD berdasarkan kapasitas dan nomor seri; SSD tidak dipilih otomatis.";
    });
    async Task Busy(Func<Task> work)
    {
        if (busy) return;
        busy = true; foreach (var c in inputs) c.Enabled = false; install.Enabled = false;
        progress.Style = ProgressBarStyle.Marquee; status.Text = "Memproses… lihat tab Log proses.";
        try { await work(); }
        catch (Exception ex) { plan = null; status.Text = "Proses dihentikan: " + ex.Message; Log("GAGAL: " + ex); MessageBox.Show(this, ex.Message + "\n\nLihat log untuk detail. Jika format sudah dimulai, data lama tidak dipulihkan otomatis.", "Proses tidak selesai", MessageBoxButtons.OK, MessageBoxIcon.Error); }
        finally { busy = false; foreach (var c in inputs) c.Enabled = true; install.Enabled = plan != null; progress.Style = ProgressBarStyle.Blocks; }
    }
    void Log(string line)
    {
        if (string.IsNullOrWhiteSpace(line)) return;
        lock (logLock) File.AppendAllText(logPath, $"{DateTime.Now:HH:mm:ss} {line}{Environment.NewLine}", Encoding.UTF8);
        if (IsHandleCreated && !IsDisposed) BeginInvoke(() => { logText.AppendText(line + Environment.NewLine); });
    }
    async Task<JsonObject> Run(JsonObject request)
    {
        var id = Guid.NewGuid().ToString("N");
        var req = Path.Combine(sessionDir, id + ".request.json");
        var res = Path.Combine(sessionDir, id + ".result.json");
        request["appPath"] = Environment.ProcessPath;
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
        if (!File.Exists(res)) throw new InvalidOperationException($"Mesin pemasangan berhenti (kode {process.ExitCode}). Periksa log; kebijakan Windows mungkin memblokir PowerShell.");
        var response = JsonNode.Parse(await File.ReadAllTextAsync(res))!.AsObject();
        if (process.ExitCode != 0 || response["ok"]?.GetValue<bool>() != true) throw new InvalidOperationException(response["error"]?.GetValue<string>() ?? "Pemasangan gagal.");
        return response["data"]!.AsObject();
    }
}

internal sealed class ConfirmForm : Form
{
    public ConfirmForm(string summary, string phrase)
    {
        Text = "Konfirmasi penghapusan SSD"; Size = new Size(750, 620); MinimumSize = Size;
        StartPosition = FormStartPosition.CenterParent; Font = new Font("Segoe UI", 10);
        var root = new TableLayoutPanel { Dock = DockStyle.Fill, Padding = new Padding(18), RowCount = 5, ColumnCount = 1 };
        root.RowStyles.Add(new RowStyle(SizeType.Percent, 100)); for (var i = 1; i < 5; i++) root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        root.Controls.Add(new TextBox { Text = summary, Multiline = true, ReadOnly = true, ScrollBars = ScrollBars.Vertical, Dock = DockStyle.Fill }, 0, 0);
        var consent = new CheckBox { Text = "Saya sudah mencadangkan data dan mengizinkan seluruh SSD ini dihapus.", AutoSize = true, Margin = new Padding(3, 15, 3, 10) };
        root.Controls.Add(consent, 0, 1);
        root.Controls.Add(new Label { Text = $"Ketik persis: {phrase}", AutoSize = true }, 0, 2);
        var text = new TextBox { Dock = DockStyle.Fill }; root.Controls.Add(text, 0, 3);
        var buttons = new FlowLayoutPanel { AutoSize = true, Dock = DockStyle.Fill };
        var yes = new Button { Text = "Hapus & pasang", AutoSize = true, Enabled = false, DialogResult = DialogResult.OK };
        var no = new Button { Text = "Batal", AutoSize = true, DialogResult = DialogResult.Cancel };
        void Check() => yes.Enabled = consent.Checked && text.Text == phrase;
        text.TextChanged += (_, _) => Check(); consent.CheckedChanged += (_, _) => Check();
        buttons.Controls.AddRange([no, yes]); root.Controls.Add(buttons, 0, 4); Controls.Add(root); CancelButton = no;
    }
}
