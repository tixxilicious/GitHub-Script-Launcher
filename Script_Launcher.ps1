#Requires -Version 5.1
<#
.SYNOPSIS
    GitHub Script Launcher v3.0
.DESCRIPTION
    GUI-Tool zum Auflisten, Herunterladen und Ausfuehren von Scripts
    aus den GitHub-Repositories von tixxilicious.
    
    Features:
    - Dark Theme mit Akzentfarben
    - Repo-Infopanel mit Beschreibung, Sprache, Sternen
    - Suchfeld fuer Repos und Scripts
    - Farbige Runtime-Badges
    - Tastaturkuerzel (F5, Enter, Ctrl+S)
    - Repo-Beschreibung & Statistiken
    
.NOTES
    Benoetigt: Windows PowerShell 5.1+, Internetverbindung
#>

$GitHubUser = "tixxilicious"
$GitHubApiBase = "https://api.github.com"
$TempDir = Join-Path $env:TEMP "GitHubScriptLauncher"
$AppVersion = "3.0"
$AppDate = "2026-02-18"

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# ============================================================
# CUSTOM DRAWING HELPERS (Owner-Draw fuer Farbbadges)
# ============================================================
Add-Type -Language CSharp @"
using System;
using System.Drawing;
using System.Windows.Forms;
using System.Collections.Generic;

public class DarkListView : ListView
{
    public DarkListView()
    {
        this.OwnerDraw = true;
        this.DoubleBuffered = true;
        this.SetStyle(ControlStyles.OptimizedDoubleBuffer | ControlStyles.AllPaintingInWmPaint, true);
    }

    private Color _headerBg = Color.FromArgb(30, 30, 30);
    private Color _headerFg = Color.FromArgb(180, 180, 180);
    private Color _itemBg1 = Color.FromArgb(32, 33, 36);
    private Color _itemBg2 = Color.FromArgb(40, 41, 45);
    private Color _selectedBg = Color.FromArgb(0, 100, 180);
    private Color _gridColor = Color.FromArgb(55, 55, 60);

    public Dictionary<string, Color> BadgeColors = new Dictionary<string, Color>();

    protected override void OnDrawColumnHeader(DrawListViewColumnHeaderEventArgs e)
    {
        using (var bg = new SolidBrush(_headerBg))
        using (var fg = new SolidBrush(_headerFg))
        using (var pen = new Pen(_gridColor))
        {
            e.Graphics.FillRectangle(bg, e.Bounds);
            var sf = new StringFormat { LineAlignment = StringAlignment.Center, Trimming = StringTrimming.EllipsisCharacter };
            var textRect = new Rectangle(e.Bounds.X + 4, e.Bounds.Y, e.Bounds.Width - 8, e.Bounds.Height);
            e.Graphics.DrawString(e.Header.Text, new Font("Segoe UI Semibold", 8.5f), fg, textRect, sf);
            e.Graphics.DrawLine(pen, e.Bounds.Right - 1, e.Bounds.Top, e.Bounds.Right - 1, e.Bounds.Bottom);
            e.Graphics.DrawLine(pen, e.Bounds.Left, e.Bounds.Bottom - 1, e.Bounds.Right, e.Bounds.Bottom - 1);
        }
    }

    protected override void OnDrawItem(DrawListViewItemEventArgs e)
    {
        e.DrawDefault = false;
    }

    protected override void OnDrawSubItem(DrawListViewSubItemEventArgs e)
    {
        bool selected = e.Item.Selected;
        Color bg = selected ? _selectedBg : (e.ItemIndex % 2 == 0 ? _itemBg1 : _itemBg2);
        
        using (var bgBrush = new SolidBrush(bg))
        {
            e.Graphics.FillRectangle(bgBrush, e.Bounds);
        }

        string text = e.SubItem.Text;
        Color textColor = selected ? Color.White : Color.FromArgb(210, 210, 210);

        // Check if this is a badge column (Runtime-Status or Typ)
        if (e.ColumnIndex == 1 && BadgeColors.ContainsKey(text))
        {
            // Draw runtime type as colored badge
            Color badgeColor = BadgeColors[text];
            var font = new Font("Segoe UI Semibold", 7.5f);
            var textSize = e.Graphics.MeasureString(text, font);
            int badgeW = (int)textSize.Width + 12;
            int badgeH = 18;
            int badgeX = e.Bounds.X + 4;
            int badgeY = e.Bounds.Y + (e.Bounds.Height - badgeH) / 2;
            
            using (var badgeBrush = new SolidBrush(Color.FromArgb(40, badgeColor)))
            using (var borderPen = new Pen(badgeColor, 1))
            using (var textBrush = new SolidBrush(badgeColor))
            {
                var rect = new Rectangle(badgeX, badgeY, badgeW, badgeH);
                var gp = RoundedRect(rect, 4);
                e.Graphics.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.AntiAlias;
                e.Graphics.FillPath(badgeBrush, gp);
                e.Graphics.DrawPath(borderPen, gp);
                var sf = new StringFormat { Alignment = StringAlignment.Center, LineAlignment = StringAlignment.Center };
                e.Graphics.DrawString(text, font, textBrush, new RectangleF(badgeX, badgeY, badgeW, badgeH), sf);
            }
            return;
        }
        
        // Check runtime status column for color
        if (e.ColumnIndex == 3)
        {
            if (text.Contains("FEHLT")) textColor = Color.FromArgb(255, 85, 85);
            else if (text.Contains("OK")) textColor = Color.FromArgb(80, 200, 120);
        }

        using (var fg = new SolidBrush(textColor))
        {
            var sf = new StringFormat { LineAlignment = StringAlignment.Center, Trimming = StringTrimming.EllipsisCharacter, FormatFlags = StringFormatFlags.NoWrap };
            var textRect = new RectangleF(e.Bounds.X + 6, e.Bounds.Y, e.Bounds.Width - 12, e.Bounds.Height);
            e.Graphics.DrawString(text, e.SubItem.Font ?? e.Item.Font, fg, textRect, sf);
        }
    }

    private static System.Drawing.Drawing2D.GraphicsPath RoundedRect(Rectangle bounds, int radius)
    {
        int d = radius * 2;
        var gp = new System.Drawing.Drawing2D.GraphicsPath();
        gp.AddArc(bounds.X, bounds.Y, d, d, 180, 90);
        gp.AddArc(bounds.Right - d, bounds.Y, d, d, 270, 90);
        gp.AddArc(bounds.Right - d, bounds.Bottom - d, d, d, 0, 90);
        gp.AddArc(bounds.X, bounds.Bottom - d, d, d, 90, 90);
        gp.CloseFigure();
        return gp;
    }
}
"@ -ReferencedAssemblies System.Windows.Forms, System.Drawing

# ============================================================
# HILFSFUNKTIONEN
# ============================================================

function Get-RuntimeStatus {
    $runtimes = @{}
    $pythonFound = $false
    $pythonPaths = @("python", "python3", "py")
    foreach ($p in $pythonPaths) {
        try {
            $cmd = Get-Command $p -ErrorAction SilentlyContinue
            if ($null -ne $cmd) {
                $versionOutput = & $p --version 2>&1 | Out-String
                if ($versionOutput -match "Python (\d+\.\d+\.\d+)") {
                    $runtimes["Python"] = @{ Available = $true; Version = $Matches[1]; Command = $cmd.Source }
                    $pythonFound = $true
                    break
                }
            }
        } catch { }
    }
    if (-not $pythonFound) {
        $runtimes["Python"] = @{ Available = $false; Version = "Nicht installiert"; Command = $null }
    }
    $runtimes["PowerShell"] = @{ Available = $true; Version = $PSVersionTable.PSVersion.ToString(); Command = "powershell.exe" }
    try {
        $nodeCmd = Get-Command "node" -ErrorAction SilentlyContinue
        if ($null -ne $nodeCmd) {
            $nv = & node --version 2>&1 | Out-String
            if ($nv -match "v(\d+\.\d+\.\d+)") {
                $runtimes["Node.js"] = @{ Available = $true; Version = $Matches[1]; Command = $nodeCmd.Source }
            } else { $runtimes["Node.js"] = @{ Available = $false; Version = "Nicht installiert"; Command = $null } }
        } else { $runtimes["Node.js"] = @{ Available = $false; Version = "Nicht installiert"; Command = $null } }
    } catch { $runtimes["Node.js"] = @{ Available = $false; Version = "Nicht installiert"; Command = $null } }
    $gitBash = "C:\Program Files\Git\bin\bash.exe"
    if (Test-Path $gitBash) { $runtimes["Bash"] = @{ Available = $true; Version = "Git Bash"; Command = $gitBash } }
    else { $runtimes["Bash"] = @{ Available = $false; Version = "Nicht installiert"; Command = $null } }
    return $runtimes
}

function Get-FileRuntime {
    param([string]$FileName)
    switch -Regex ($FileName) {
        '\.py$'  { return "Python" }
        '\.ps1$' { return "PowerShell" }
        '\.js$'  { return "Node.js" }
        '\.sh$'  { return "Bash" }
        '\.bat$' { return "CMD" }
        '\.cmd$' { return "CMD" }
        default  { return "Unbekannt" }
    }
}

function Get-GitHubRepos {
    try {
        $h = @{ "User-Agent" = "GitHubScriptLauncher/3.0" }
        return (Invoke-RestMethod -Uri "$GitHubApiBase/users/$GitHubUser/repos?per_page=100&sort=updated" -Headers $h -ErrorAction Stop)
    } catch { return $null }
}

function Get-RepoContents {
    param([string]$RepoName, [string]$Path = "")
    try {
        $h = @{ "User-Agent" = "GitHubScriptLauncher/3.0" }
        return (Invoke-RestMethod -Uri "$GitHubApiBase/repos/$GitHubUser/$RepoName/contents/$Path" -Headers $h -ErrorAction Stop)
    } catch { return $null }
}

function Get-ScriptFilesRecursive {
    param([string]$RepoName, [string]$Path = "")
    $exts = @('.py', '.ps1', '.js', '.sh', '.bat', '.cmd')
    $results = @()
    $contents = Get-RepoContents -RepoName $RepoName -Path $Path
    if ($null -eq $contents) { return $results }
    if ($contents -isnot [Array]) { $contents = @($contents) }
    foreach ($item in $contents) {
        if ($item.type -eq "file") {
            $ext = [System.IO.Path]::GetExtension($item.name).ToLower()
            if ($ext -in $exts) {
                $results += [PSCustomObject]@{
                    Name = $item.name; Path = $item.path
                    DownloadUrl = $item.download_url; Size = $item.size
                    Runtime = Get-FileRuntime -FileName $item.name
                }
            }
        } elseif ($item.type -eq "dir") {
            $results += Get-ScriptFilesRecursive -RepoName $RepoName -Path $item.path
        }
    }
    return $results
}

function Download-Script {
    param([string]$DownloadUrl, [string]$RepoName, [string]$FilePath)
    $dir = Join-Path $TempDir $RepoName
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $file = Join-Path $dir (Split-Path $FilePath -Leaf)
    try { Invoke-WebRequest -Uri $DownloadUrl -OutFile $file -ErrorAction Stop; return $file }
    catch { return $null }
}

function Check-PythonRequirements {
    param([string]$RepoName, [string]$PythonCommand)
    if ([string]::IsNullOrEmpty($PythonCommand)) { return $false }
    $contents = Get-RepoContents -RepoName $RepoName
    if ($null -eq $contents) { return $true }
    $reqFile = $contents | Where-Object { $_.name -eq "requirements.txt" }
    if ($reqFile) {
        $localReq = Download-Script -DownloadUrl $reqFile.download_url -RepoName $RepoName -FilePath "requirements.txt"
        if ($localReq) {
            $r = [System.Windows.Forms.MessageBox]::Show(
                "requirements.txt gefunden. Abhaengigkeiten installieren?",
                "Python Dependencies", "YesNo", "Question")
            if ($r -eq "Yes") {
                $p = Start-Process -FilePath $PythonCommand -ArgumentList "-m pip install -r `"$localReq`"" -NoNewWindow -Wait -PassThru
                if ($p.ExitCode -ne 0) {
                    [System.Windows.Forms.MessageBox]::Show("Fehler bei pip install!", "Fehler", 0, 48)
                    return $false
                }
            }
        }
    }
    return $true
}

function Format-TimeAgo {
    param([datetime]$Date)
    $span = (Get-Date) - $Date
    if ($span.TotalMinutes -lt 60) { return "vor $([math]::Floor($span.TotalMinutes)) Min." }
    if ($span.TotalHours -lt 24) { return "vor $([math]::Floor($span.TotalHours)) Std." }
    if ($span.TotalDays -lt 30) { return "vor $([math]::Floor($span.TotalDays)) Tagen" }
    if ($span.TotalDays -lt 365) { return "vor $([math]::Floor($span.TotalDays / 30)) Mon." }
    return "vor $([math]::Floor($span.TotalDays / 365)) J."
}

# ============================================================
# FARBEN - Dark Theme
# ============================================================
$cBg         = [System.Drawing.Color]::FromArgb(22, 22, 26)
$cBgPanel    = [System.Drawing.Color]::FromArgb(30, 31, 34)
$cBgInput    = [System.Drawing.Color]::FromArgb(38, 39, 43)
$cBorder     = [System.Drawing.Color]::FromArgb(55, 55, 60)
$cHeader     = [System.Drawing.Color]::FromArgb(15, 15, 18)
$cAccent     = [System.Drawing.Color]::FromArgb(88, 166, 255)
$cGreen      = [System.Drawing.Color]::FromArgb(63, 185, 80)
$cOrange     = [System.Drawing.Color]::FromArgb(210, 153, 34)
$cRed        = [System.Drawing.Color]::FromArgb(248, 81, 73)
$cGray       = [System.Drawing.Color]::FromArgb(110, 118, 129)
$cTextMain   = [System.Drawing.Color]::FromArgb(230, 237, 243)
$cTextDim    = [System.Drawing.Color]::FromArgb(139, 148, 158)
$cEditorBg   = [System.Drawing.Color]::FromArgb(13, 17, 23)
$cEditorFg   = [System.Drawing.Color]::FromArgb(201, 209, 217)
$cPurple     = [System.Drawing.Color]::FromArgb(163, 113, 247)

# Runtime Badge Colors
$badgeColorMap = @{
    "Python"     = [System.Drawing.Color]::FromArgb(53, 114, 165)
    "PowerShell" = [System.Drawing.Color]::FromArgb(1, 36, 86)
    "Node.js"    = [System.Drawing.Color]::FromArgb(51, 153, 51)
    "Bash"       = [System.Drawing.Color]::FromArgb(137, 224, 81)
    "CMD"        = [System.Drawing.Color]::FromArgb(180, 180, 180)
    "Unbekannt"  = [System.Drawing.Color]::FromArgb(110, 110, 110)
}

# ============================================================
# GUI
# ============================================================
$form = New-Object System.Windows.Forms.Form
$form.Text = "GitHub Script Launcher v$AppVersion - @$GitHubUser"
$form.ClientSize = New-Object System.Drawing.Size(960, 640)
$form.MinimumSize = New-Object System.Drawing.Size(800, 540)
$form.StartPosition = "CenterScreen"
$form.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$form.BackColor = $cBg
$form.ForeColor = $cTextMain
$form.KeyPreview = $true

# --- Header ---
$pnlHeader = New-Object System.Windows.Forms.Panel
$pnlHeader.Dock = "Top"
$pnlHeader.Height = 52
$pnlHeader.BackColor = $cHeader

$lblTitle = New-Object System.Windows.Forms.Label
$lblTitle.Text = [char]0x2B50 + " GitHub Script Launcher"
$lblTitle.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 15)
$lblTitle.ForeColor = [System.Drawing.Color]::White
$lblTitle.Location = New-Object System.Drawing.Point(16, 12)
$lblTitle.AutoSize = $true
$pnlHeader.Controls.Add($lblTitle)

$lblUser = New-Object System.Windows.Forms.Label
$lblUser.Text = "@$GitHubUser"
$lblUser.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$lblUser.ForeColor = $cAccent
$lblUser.Location = New-Object System.Drawing.Point(310, 16)
$lblUser.AutoSize = $true
$lblUser.Cursor = "Hand"
$pnlHeader.Controls.Add($lblUser)

$lblVersion = New-Object System.Windows.Forms.Label
$lblVersion.Text = "v$AppVersion  |  $AppDate"
$lblVersion.Font = New-Object System.Drawing.Font("Segoe UI", 8)
$lblVersion.ForeColor = $cGray
$lblVersion.Anchor = "Top,Right"
$lblVersion.AutoSize = $true
$lblVersion.Location = New-Object System.Drawing.Point(($form.ClientSize.Width - 155), 20)
$pnlHeader.Controls.Add($lblVersion)

$form.Controls.Add($pnlHeader)

# --- StatusBar ---
$statusStrip = New-Object System.Windows.Forms.StatusStrip
$statusStrip.BackColor = $cHeader
$statusStrip.ForeColor = $cTextDim
$statusLabel = New-Object System.Windows.Forms.ToolStripStatusLabel("Bereit")
$statusLabel.ForeColor = $cTextDim
$statusStrip.Items.Add($statusLabel) | Out-Null
$shortcutLabel = New-Object System.Windows.Forms.ToolStripStatusLabel("F5 Aktualisieren  |  Enter Ausfuehren  |  Ctrl+S Speichern")
$shortcutLabel.Alignment = "Right"
$shortcutLabel.ForeColor = [System.Drawing.Color]::FromArgb(80, 80, 90)
$statusStrip.Items.Add((New-Object System.Windows.Forms.ToolStripStatusLabel("") -Property @{ Spring = $true })) | Out-Null
$statusStrip.Items.Add($shortcutLabel) | Out-Null
$form.Controls.Add($statusStrip)

# --- Left Column: Repos ---
$leftW = 250

$lblRepos = New-Object System.Windows.Forms.Label
$lblRepos.Text = "REPOSITORIES"
$lblRepos.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 8)
$lblRepos.ForeColor = $cTextDim
$lblRepos.Location = New-Object System.Drawing.Point(12, 60)
$lblRepos.Size = New-Object System.Drawing.Size(160, 16)
$form.Controls.Add($lblRepos)

# Repo Search
$txtRepoSearch = New-Object System.Windows.Forms.TextBox
$txtRepoSearch.Location = New-Object System.Drawing.Point(12, 79)
$txtRepoSearch.Size = New-Object System.Drawing.Size($leftW, 26)
$txtRepoSearch.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$txtRepoSearch.BackColor = $cBgInput
$txtRepoSearch.ForeColor = $cTextMain
$txtRepoSearch.BorderStyle = "FixedSingle"
$txtRepoSearch.Text = ""
$form.Controls.Add($txtRepoSearch)

# Placeholder Label fuer Suchfeld
$lblSearchPlaceholder = New-Object System.Windows.Forms.Label
$lblSearchPlaceholder.Text = "Repos durchsuchen..."
$lblSearchPlaceholder.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$lblSearchPlaceholder.ForeColor = $cGray
$lblSearchPlaceholder.BackColor = $cBgInput
$lblSearchPlaceholder.Location = New-Object System.Drawing.Point(15, 82)
$lblSearchPlaceholder.Size = New-Object System.Drawing.Size(200, 20)
$lblSearchPlaceholder.Cursor = "IBeam"
$form.Controls.Add($lblSearchPlaceholder)
$lblSearchPlaceholder.BringToFront()

$lstRepos = New-Object System.Windows.Forms.ListBox
$lstRepos.Location = New-Object System.Drawing.Point(12, 108)
$lstRepos.Size = New-Object System.Drawing.Size($leftW, 370)
$lstRepos.Anchor = "Top,Left,Bottom"
$lstRepos.Font = New-Object System.Drawing.Font("Segoe UI", 9.5)
$lstRepos.BackColor = $cBgPanel
$lstRepos.ForeColor = $cTextMain
$lstRepos.BorderStyle = "None"
$lstRepos.IntegralHeight = $false
$lstRepos.DrawMode = "OwnerDrawFixed"
$lstRepos.ItemHeight = 38
$form.Controls.Add($lstRepos)

# Repo Info Panel
$pnlRepoInfo = New-Object System.Windows.Forms.Panel
$pnlRepoInfo.Location = New-Object System.Drawing.Point(12, 482)
$pnlRepoInfo.Size = New-Object System.Drawing.Size($leftW, 70)
$pnlRepoInfo.Anchor = "Left,Bottom"
$pnlRepoInfo.BackColor = $cBgPanel
$form.Controls.Add($pnlRepoInfo)

$lblRepoDesc = New-Object System.Windows.Forms.Label
$lblRepoDesc.Text = "Waehle ein Repository..."
$lblRepoDesc.Font = New-Object System.Drawing.Font("Segoe UI", 8.5)
$lblRepoDesc.ForeColor = $cTextDim
$lblRepoDesc.Location = New-Object System.Drawing.Point(8, 6)
$lblRepoDesc.Size = New-Object System.Drawing.Size(($leftW - 16), 34)
$pnlRepoInfo.Controls.Add($lblRepoDesc)

$lblRepoStats = New-Object System.Windows.Forms.Label
$lblRepoStats.Text = ""
$lblRepoStats.Font = New-Object System.Drawing.Font("Segoe UI", 8)
$lblRepoStats.ForeColor = $cGray
$lblRepoStats.Location = New-Object System.Drawing.Point(8, 44)
$lblRepoStats.Size = New-Object System.Drawing.Size(($leftW - 16), 20)
$pnlRepoInfo.Controls.Add($lblRepoStats)

$btnRefresh = New-Object System.Windows.Forms.Button
$btnRefresh.Text = "Aktualisieren (F5)"
$btnRefresh.Location = New-Object System.Drawing.Point(12, 556)
$btnRefresh.Size = New-Object System.Drawing.Size($leftW, 32)
$btnRefresh.Anchor = "Left,Bottom"
$btnRefresh.FlatStyle = "Flat"
$btnRefresh.BackColor = $cBgInput
$btnRefresh.ForeColor = $cTextMain
$btnRefresh.FlatAppearance.BorderColor = $cBorder
$btnRefresh.FlatAppearance.BorderSize = 1
$btnRefresh.Cursor = "Hand"
$form.Controls.Add($btnRefresh)

# --- Right Column ---
$rightX = 274
$rightW = 674

$lblScripts = New-Object System.Windows.Forms.Label
$lblScripts.Text = "SCRIPTS"
$lblScripts.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 8)
$lblScripts.ForeColor = $cTextDim
$lblScripts.Location = New-Object System.Drawing.Point($rightX, 60)
$lblScripts.Size = New-Object System.Drawing.Size(100, 16)
$form.Controls.Add($lblScripts)

$lblScriptCount = New-Object System.Windows.Forms.Label
$lblScriptCount.Text = ""
$lblScriptCount.Font = New-Object System.Drawing.Font("Segoe UI", 8)
$lblScriptCount.ForeColor = $cGray
$lblScriptCount.Location = New-Object System.Drawing.Point(($rightX + 65), 60)
$lblScriptCount.Size = New-Object System.Drawing.Size(200, 16)
$lblScriptCount.Anchor = "Top,Left"
$form.Controls.Add($lblScriptCount)

# Scripts ListView mit Custom Drawing
$lvScripts = New-Object DarkListView
$lvScripts.Location = New-Object System.Drawing.Point($rightX, 79)
$lvScripts.Size = New-Object System.Drawing.Size($rightW, 190)
$lvScripts.Anchor = "Top,Left,Right"
$lvScripts.View = "Details"
$lvScripts.FullRowSelect = $true
$lvScripts.GridLines = $false
$lvScripts.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$lvScripts.BackColor = [System.Drawing.Color]::FromArgb(32, 33, 36)
$lvScripts.ForeColor = $cTextMain
$lvScripts.BorderStyle = "None"
$lvScripts.HeaderStyle = "Nonclickable"
$lvScripts.Columns.Add("Datei", 280) | Out-Null
$lvScripts.Columns.Add("Typ", 95) | Out-Null
$lvScripts.Columns.Add("Groesse", 80) | Out-Null
$lvScripts.Columns.Add("Runtime-Status", 200) | Out-Null

# Badge-Farben setzen
foreach ($key in $badgeColorMap.Keys) {
    $lvScripts.BadgeColors[$key] = $badgeColorMap[$key]
}

$form.Controls.Add($lvScripts)

# Vorschau Label
$lblPreview = New-Object System.Windows.Forms.Label
$lblPreview.Text = "VORSCHAU"
$lblPreview.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 8)
$lblPreview.ForeColor = $cTextDim
$lblPreview.Location = New-Object System.Drawing.Point($rightX, 276)
$lblPreview.Size = New-Object System.Drawing.Size(100, 16)
$form.Controls.Add($lblPreview)

$lblPreviewFile = New-Object System.Windows.Forms.Label
$lblPreviewFile.Text = ""
$lblPreviewFile.Font = New-Object System.Drawing.Font("Segoe UI", 8)
$lblPreviewFile.ForeColor = $cAccent
$lblPreviewFile.Location = New-Object System.Drawing.Point(($rightX + 75), 276)
$lblPreviewFile.Size = New-Object System.Drawing.Size(500, 16)
$lblPreviewFile.Anchor = "Top,Left,Right"
$form.Controls.Add($lblPreviewFile)

$txtPreview = New-Object System.Windows.Forms.RichTextBox
$txtPreview.Location = New-Object System.Drawing.Point($rightX, 295)
$txtPreview.Size = New-Object System.Drawing.Size($rightW, 245)
$txtPreview.Anchor = "Top,Left,Right,Bottom"
$txtPreview.ReadOnly = $true
$txtPreview.Font = New-Object System.Drawing.Font("Cascadia Code,Consolas,Courier New", 9)
$txtPreview.BackColor = $cEditorBg
$txtPreview.ForeColor = $cEditorFg
$txtPreview.WordWrap = $false
$txtPreview.BorderStyle = "None"
$txtPreview.Text = "  Waehle ein Repository und ein Script aus..."
$form.Controls.Add($txtPreview)

# --- Buttons ---
$btnRun = New-Object System.Windows.Forms.Button
$btnRun.Text = [char]0x25B6 + " Ausfuehren"
$btnRun.Location = New-Object System.Drawing.Point($rightX, 548)
$btnRun.Size = New-Object System.Drawing.Size(130, 34)
$btnRun.Anchor = "Left,Bottom"
$btnRun.FlatStyle = "Flat"
$btnRun.BackColor = $cGreen
$btnRun.ForeColor = [System.Drawing.Color]::White
$btnRun.FlatAppearance.BorderSize = 0
$btnRun.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 10)
$btnRun.Cursor = "Hand"
$btnRun.Enabled = $false
$form.Controls.Add($btnRun)

$btnSave = New-Object System.Windows.Forms.Button
$btnSave.Text = "Speichern unter..."
$btnSave.Location = New-Object System.Drawing.Point(($rightX + 140), 548)
$btnSave.Size = New-Object System.Drawing.Size(140, 34)
$btnSave.Anchor = "Left,Bottom"
$btnSave.FlatStyle = "Flat"
$btnSave.BackColor = $cAccent
$btnSave.ForeColor = [System.Drawing.Color]::White
$btnSave.FlatAppearance.BorderSize = 0
$btnSave.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 9.5)
$btnSave.Cursor = "Hand"
$btnSave.Enabled = $false
$form.Controls.Add($btnSave)

$btnRuntime = New-Object System.Windows.Forms.Button
$btnRuntime.Text = "Runtime-Check"
$btnRuntime.Location = New-Object System.Drawing.Point(($rightX + 290), 548)
$btnRuntime.Size = New-Object System.Drawing.Size(130, 34)
$btnRuntime.Anchor = "Left,Bottom"
$btnRuntime.FlatStyle = "Flat"
$btnRuntime.BackColor = $cBgInput
$btnRuntime.ForeColor = $cTextMain
$btnRuntime.FlatAppearance.BorderColor = $cBorder
$btnRuntime.FlatAppearance.BorderSize = 1
$btnRuntime.Cursor = "Hand"
$form.Controls.Add($btnRuntime)

$btnOpenGH = New-Object System.Windows.Forms.Button
$btnOpenGH.Text = "Auf GitHub oeffnen"
$btnOpenGH.Location = New-Object System.Drawing.Point(($rightX + 430), 548)
$btnOpenGH.Size = New-Object System.Drawing.Size(150, 34)
$btnOpenGH.Anchor = "Left,Bottom"
$btnOpenGH.FlatStyle = "Flat"
$btnOpenGH.BackColor = $cBgInput
$btnOpenGH.ForeColor = $cTextDim
$btnOpenGH.FlatAppearance.BorderColor = $cBorder
$btnOpenGH.FlatAppearance.BorderSize = 1
$btnOpenGH.Cursor = "Hand"
$btnOpenGH.Enabled = $false
$form.Controls.Add($btnOpenGH)

# Separator line between left and right
$pnlSep = New-Object System.Windows.Forms.Panel
$pnlSep.Location = New-Object System.Drawing.Point(268, 56)
$pnlSep.Size = New-Object System.Drawing.Size(1, 536)
$pnlSep.Anchor = "Top,Left,Bottom"
$pnlSep.BackColor = $cBorder
$form.Controls.Add($pnlSep)

# ============================================================
# STATE
# ============================================================
$script:repoData = @{}
$script:allRepoNames = @()
$script:scriptData = @()
$script:runtimes = @{}
$script:selectedScript = $null

# ============================================================
# OWNER DRAW: Repo ListBox
# ============================================================
$lstRepos.Add_DrawItem({
    param($s, $e)
    if ($e.Index -lt 0) { return }
    $e.DrawBackground()
    
    $repoName = $lstRepos.Items[$e.Index].ToString()
    $isSelected = ($e.State -band [System.Windows.Forms.DrawItemState]::Selected)
    
    $bgColor = if ($isSelected) { [System.Drawing.Color]::FromArgb(0, 100, 180) }
               elseif ($e.Index % 2 -eq 0) { $cBgPanel }
               else { [System.Drawing.Color]::FromArgb(35, 36, 40) }
    
    $g = $e.Graphics
    $g.FillRectangle((New-Object System.Drawing.SolidBrush($bgColor)), $e.Bounds)
    
    # Repo Name
    $nameFont = New-Object System.Drawing.Font("Segoe UI Semibold", 9.5)
    $nameColor = if ($isSelected) { [System.Drawing.Color]::White } else { $cTextMain }
    $g.DrawString($repoName, $nameFont, (New-Object System.Drawing.SolidBrush($nameColor)), ($e.Bounds.X + 10), ($e.Bounds.Y + 2))
    
    # Datum
    $repo = $script:repoData[$repoName]
    if ($null -ne $repo -and $repo.updated_at) {
        try {
            $dt = [datetime]::Parse($repo.updated_at)
            $ago = Format-TimeAgo -Date $dt
            $dateFont = New-Object System.Drawing.Font("Segoe UI", 7.5)
            $dateColor = if ($isSelected) { [System.Drawing.Color]::FromArgb(200, 200, 200) } else { $cGray }
            $g.DrawString($ago, $dateFont, (New-Object System.Drawing.SolidBrush($dateColor)), ($e.Bounds.X + 10), ($e.Bounds.Y + 20))
            
            # Sprache als kleiner Badge
            if ($repo.language) {
                $langFont = New-Object System.Drawing.Font("Segoe UI", 7)
                $langSize = $g.MeasureString($repo.language, $langFont)
                $langX = $e.Bounds.Right - $langSize.Width - 14
                $langColor = if ($isSelected) { [System.Drawing.Color]::FromArgb(180, 220, 255) } else { $cAccent }
                $g.DrawString($repo.language, $langFont, (New-Object System.Drawing.SolidBrush($langColor)), $langX, ($e.Bounds.Y + 20))
            }
        } catch { }
    }
    
    $e.DrawFocusRectangle()
})

# ============================================================
# EVENTS
# ============================================================

$loadRepos = {
    $statusLabel.Text = "Lade Repositories..."
    $form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
    $lstRepos.Items.Clear()
    $script:repoData = @{}
    $script:allRepoNames = @()

    $repos = Get-GitHubRepos
    if ($null -eq $repos) {
        $statusLabel.Text = "Fehler beim Laden!"
        [System.Windows.Forms.MessageBox]::Show("Repos konnten nicht geladen werden.`nInternetverbindung pruefen.", "Fehler", 0, 16)
        $form.Cursor = [System.Windows.Forms.Cursors]::Default
        return
    }
    foreach ($repo in $repos) {
        $script:repoData[$repo.name] = $repo
        $script:allRepoNames += $repo.name
        $lstRepos.Items.Add($repo.name) | Out-Null
    }
    $statusLabel.Text = "$($repos.Count) Repositories geladen"
    $form.Cursor = [System.Windows.Forms.Cursors]::Default
}

# Repo Search
$txtRepoSearch.Add_TextChanged({
    $search = $txtRepoSearch.Text.ToLower()
    $lblSearchPlaceholder.Visible = [string]::IsNullOrEmpty($search)
    $lstRepos.Items.Clear()
    foreach ($name in $script:allRepoNames) {
        if ([string]::IsNullOrEmpty($search) -or $name.ToLower().Contains($search)) {
            $lstRepos.Items.Add($name) | Out-Null
        }
    }
})
$txtRepoSearch.Add_GotFocus({ $lblSearchPlaceholder.Visible = $false })
$txtRepoSearch.Add_LostFocus({ if ([string]::IsNullOrEmpty($txtRepoSearch.Text)) { $lblSearchPlaceholder.Visible = $true } })
$lblSearchPlaceholder.Add_Click({ $txtRepoSearch.Focus() })

$lstRepos.Add_SelectedIndexChanged({
    if ($null -eq $lstRepos.SelectedItem) { return }
    $repoName = $lstRepos.SelectedItem.ToString()
    
    # Repo Info updaten
    $repo = $script:repoData[$repoName]
    if ($null -ne $repo) {
        $desc = if ($repo.description) { $repo.description } else { "Keine Beschreibung" }
        $lblRepoDesc.Text = $desc
        
        $stats = @()
        if ($repo.language) { $stats += $repo.language }
        if ($repo.stargazers_count -gt 0) { $stats += "$([char]0x2B50)$($repo.stargazers_count)" }
        if ($repo.forks_count -gt 0) { $stats += "$([char]0x2442)$($repo.forks_count)" }
        try {
            $dt = [datetime]::Parse($repo.updated_at)
            $stats += "Aktualisiert: $($dt.ToString('dd.MM.yyyy HH:mm'))"
        } catch { }
        $lblRepoStats.Text = $stats -join "  |  "
        $btnOpenGH.Enabled = $true
    }
    
    $statusLabel.Text = "Suche Scripts in '$repoName'..."
    $form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
    $lvScripts.Items.Clear()
    $script:scriptData = @()
    $script:selectedScript = $null
    $btnRun.Enabled = $false
    $btnSave.Enabled = $false
    $txtPreview.Text = ""
    $lblPreviewFile.Text = ""
    $lblScriptCount.Text = ""

    if ($script:runtimes.Count -eq 0) { $script:runtimes = Get-RuntimeStatus }

    $scripts = Get-ScriptFilesRecursive -RepoName $repoName
    $script:scriptData = $scripts

    if ($scripts.Count -eq 0) {
        $txtPreview.Text = "  Keine ausfuehrbaren Scripts gefunden.`r`n`r`n  Unterstuetzt: .py .ps1 .js .sh .bat .cmd"
        $statusLabel.Text = "Keine Scripts in '$repoName'"
        $lblScriptCount.Text = "(0 Scripts)"
    } else {
        foreach ($s in $scripts) {
            $rt = $s.Runtime
            $rtInfo = $null
            if ($script:runtimes.ContainsKey($rt)) { $rtInfo = $script:runtimes[$rt] }
            
            if ($rt -eq "CMD") { $status = "[OK] Verfuegbar" }
            elseif ($rt -eq "Unbekannt") { $status = "[?] Unbekannt" }
            elseif ($null -ne $rtInfo -and $rtInfo.Available) { $status = "[OK] $($rtInfo.Version)" }
            else { $status = "[FEHLT] Nicht installiert" }

            $sizeKB = [math]::Round($s.Size / 1024, 1)
            $sizeText = if ($sizeKB -lt 1) { "$($s.Size) B" } else { "$sizeKB KB" }

            $item = New-Object System.Windows.Forms.ListViewItem($s.Path)
            $item.SubItems.Add($s.Runtime) | Out-Null
            $item.SubItems.Add($sizeText) | Out-Null
            $item.SubItems.Add($status) | Out-Null
            $item.Tag = $s
            $lvScripts.Items.Add($item) | Out-Null
        }
        $statusLabel.Text = "$($scripts.Count) Script(s) in '$repoName'"
        $lblScriptCount.Text = "($($scripts.Count) Scripts)"
    }
    $form.Cursor = [System.Windows.Forms.Cursors]::Default
})

$lvScripts.Add_SelectedIndexChanged({
    if ($lvScripts.SelectedItems.Count -eq 0) { return }
    $script:selectedScript = $lvScripts.SelectedItems[0].Tag
    $btnRun.Enabled = $true
    $btnSave.Enabled = $true
    $lblPreviewFile.Text = $script:selectedScript.Path
    $statusLabel.Text = "Lade Vorschau..."
    $form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
    try {
        $content = (Invoke-WebRequest -Uri $script:selectedScript.DownloadUrl -UseBasicParsing).Content
        $txtPreview.Text = $content
    } catch {
        $txtPreview.Text = "Fehler: $($_.Exception.Message)"
    }
    $form.Cursor = [System.Windows.Forms.Cursors]::Default
    $statusLabel.Text = "Vorschau: $($script:selectedScript.Path)"
})

$btnRun.Add_Click({
    if ($null -eq $script:selectedScript) { return }
    $s = $script:selectedScript
    $rt = $s.Runtime

    if ($rt -ne "CMD" -and $rt -ne "Unbekannt") {
        $rtInfo = $null
        if ($script:runtimes.ContainsKey($rt)) { $rtInfo = $script:runtimes[$rt] }
        if ($null -eq $rtInfo -or -not $rtInfo.Available) {
            [System.Windows.Forms.MessageBox]::Show(
                "Runtime '$rt' ist nicht installiert!`n`nBitte installiere die benoetigte Runtime und klicke dann 'Runtime-Check'.",
                "Runtime fehlt", 0, 48)
            return
        }
        if ([string]::IsNullOrEmpty($rtInfo.Command)) {
            [System.Windows.Forms.MessageBox]::Show(
                "Runtime '$rt' wurde erkannt, aber der Pfad konnte nicht ermittelt werden.",
                "Runtime-Pfad fehlt", 0, 48)
            return
        }
    }

    $confirm = [System.Windows.Forms.MessageBox]::Show(
        "Script ausfuehren?`n`nDatei: $($s.Path)`nTyp: $rt`n`nWird von GitHub geladen und lokal ausgefuehrt.",
        "Bestaetigung", "YesNo", "Question")
    if ($confirm -ne "Yes") { return }

    $statusLabel.Text = "Lade herunter..."
    $form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
    $repoName = $lstRepos.SelectedItem.ToString()
    $localFile = Download-Script -DownloadUrl $s.DownloadUrl -RepoName $repoName -FilePath $s.Path

    if ($null -eq $localFile) {
        [System.Windows.Forms.MessageBox]::Show("Download fehlgeschlagen!", "Fehler", 0, 16)
        $form.Cursor = [System.Windows.Forms.Cursors]::Default
        return
    }

    if ($rt -eq "Python") {
        $pyCmd = $null
        if ($script:runtimes.ContainsKey("Python") -and $null -ne $script:runtimes["Python"]) {
            $pyCmd = $script:runtimes["Python"].Command
        }
        if ([string]::IsNullOrEmpty($pyCmd)) {
            [System.Windows.Forms.MessageBox]::Show("Python-Pfad konnte nicht ermittelt werden!", "Fehler", 0, 48)
            $form.Cursor = [System.Windows.Forms.Cursors]::Default
            return
        }
        if (-not (Check-PythonRequirements -RepoName $repoName -PythonCommand $pyCmd)) {
            $form.Cursor = [System.Windows.Forms.Cursors]::Default
            return
        }
    }

    $form.Cursor = [System.Windows.Forms.Cursors]::Default
    $statusLabel.Text = "Starte: $($s.Name)"

    try {
        switch ($rt) {
            "Python" {
                $pyCmd = $script:runtimes["Python"].Command
                Start-Process cmd.exe -ArgumentList "/k", "`"`"$pyCmd`" `"$localFile`" & echo. & echo --- Beendet --- & pause`""
            }
            "PowerShell" {
                Start-Process powershell.exe -ArgumentList "-NoExit", "-ExecutionPolicy", "Bypass", "-File", "`"$localFile`""
            }
            "Node.js" {
                $nodeCmd = $script:runtimes["Node.js"].Command
                Start-Process cmd.exe -ArgumentList "/k", "`"`"$nodeCmd`" `"$localFile`" & echo. & echo --- Beendet --- & pause`""
            }
            "Bash" {
                $bashCmd = $script:runtimes["Bash"].Command
                Start-Process -FilePath $bashCmd -ArgumentList "`"$localFile`""
            }
            "CMD" {
                Start-Process cmd.exe -ArgumentList "/k", "`"$localFile`""
            }
            default {
                [System.Windows.Forms.MessageBox]::Show("Gespeichert unter:`n$localFile", "Info", 0, 64)
            }
        }
        $statusLabel.Text = "Gestartet: $($s.Name)"
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Fehler beim Starten:`n$($_.Exception.Message)", "Fehler", 0, 16)
    }
})

$btnSave.Add_Click({
    if ($null -eq $script:selectedScript) { return }
    $s = $script:selectedScript
    $dlg = New-Object System.Windows.Forms.SaveFileDialog
    $dlg.FileName = $s.Name
    $ext = [System.IO.Path]::GetExtension($s.Name)
    $dlg.Filter = "Script (*$ext)|*$ext|Alle (*.*)|*.*"
    if ($dlg.ShowDialog() -eq "OK") {
        try {
            Invoke-WebRequest -Uri $s.DownloadUrl -OutFile $dlg.FileName -UseBasicParsing
            $statusLabel.Text = "Gespeichert!"
            [System.Windows.Forms.MessageBox]::Show("Gespeichert:`n$($dlg.FileName)", "OK", 0, 64)
        } catch {
            [System.Windows.Forms.MessageBox]::Show("Fehler: $($_.Exception.Message)", "Fehler", 0, 16)
        }
    }
})

$btnOpenGH.Add_Click({
    if ($null -eq $lstRepos.SelectedItem) { return }
    $repoName = $lstRepos.SelectedItem.ToString()
    Start-Process "https://github.com/$GitHubUser/$repoName"
})

$lblUser.Add_Click({
    Start-Process "https://github.com/$GitHubUser"
})

$btnRuntime.Add_Click({
    $script:runtimes = Get-RuntimeStatus
    $lines = @()
    $lines += "  === Runtime-Check ==="
    $lines += ""
    foreach ($r in $script:runtimes.GetEnumerator() | Sort-Object Name) {
        $icon = if ($r.Value.Available) { [char]0x2705 } else { [char]0x274C }
        $lines += "  $icon $($r.Key): $($r.Value.Version)"
        if ($r.Value.Available -and -not [string]::IsNullOrEmpty($r.Value.Command)) {
            $lines += "     Pfad: $($r.Value.Command)"
        }
        $lines += ""
    }
    $txtPreview.Text = $lines -join "`r`n"
    $lblPreviewFile.Text = "Runtime-Check"
    $statusLabel.Text = "Runtime-Check abgeschlossen"
})

# Keyboard Shortcuts
$form.Add_KeyDown({
    param($s, $e)
    if ($e.KeyCode -eq "F5") { & $loadRepos; $e.Handled = $true }
    elseif ($e.KeyCode -eq "Return" -and $btnRun.Enabled -and -not $txtRepoSearch.Focused) { $btnRun.PerformClick(); $e.Handled = $true }
    elseif ($e.Control -and $e.KeyCode -eq "S" -and $btnSave.Enabled) { $btnSave.PerformClick(); $e.Handled = $true }
})

$btnRefresh.Add_Click({ & $loadRepos })
$lvScripts.Add_DoubleClick({ if ($btnRun.Enabled) { $btnRun.PerformClick() } })

# ============================================================
# START
# ============================================================
$form.Add_Shown({ $script:runtimes = Get-RuntimeStatus; & $loadRepos })
$form.Add_FormClosing({
    if (Test-Path $TempDir) { Remove-Item $TempDir -Recurse -Force -ErrorAction SilentlyContinue }
})
[void]$form.ShowDialog()