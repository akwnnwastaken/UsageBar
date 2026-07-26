; UsageBar — Windows installer
;
; A per-user, non-elevated install of the tray application. It installs
; UsageBar's own files and nothing else: no services, no drivers, no scheduled
; tasks, no PATH changes, no provider dependencies, and no second autostart
; mechanism — the application already owns its own HKCU Run preference.
;
; The payload is the staging directory the portable package was built from, so
; the installed build and the portable ZIP can never drift apart.
;
; Required defines (supplied by scripts/package-installer.ps1):
;   AppVersion    the version from windows/Directory.Build.props
;   PayloadDir    the verified staging directory to install
;   OutputDir     where the Setup EXE is written

#ifndef AppVersion
  #error AppVersion must be defined by the packaging script
#endif
#ifndef PayloadDir
  #error PayloadDir must be defined by the packaging script
#endif
#ifndef OutputDir
  #error OutputDir must be defined by the packaging script
#endif

#define AppName        "UsageBar"
#define AppPublisher   "UsageBar contributors"
#define AppExeName     "UsageBar.exe"
#define AppUrl         "https://github.com/akwnnwastaken/UsageBar"

[Setup]
; Stable identity. This GUID is permanent: it is what lets a newer installer
; upgrade an existing installation in place, keeps a single entry in Installed
; Apps, and prevents duplicate uninstall entries. It must never be regenerated
; for a build or changed between UsageBar versions.
AppId={{7F3B1C64-9A2E-4D58-B0E7-3C6A5D142E90}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
VersionInfoVersion={#AppVersion}
VersionInfoProductVersion={#AppVersion}
VersionInfoProductName={#AppName}
VersionInfoCompany={#AppPublisher}
VersionInfoDescription={#AppName} Setup
VersionInfoCopyright=UsageBar contributors
AppPublisher={#AppPublisher}
AppPublisherURL={#AppUrl}
AppSupportURL={#AppUrl}
AppUpdatesURL={#AppUrl}

; Per-user only. `lowest` means the installer runs unelevated, so Windows shows
; no UAC prompt, and nothing is written outside the user's own profile.
; PrivilegesRequiredOverridesAllowed is deliberately left unset so an all-users
; or elevated install cannot be selected by accident or by command line.
PrivilegesRequired=lowest
DefaultDirName={localappdata}\Programs\{#AppName}
DisableDirPage=no
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
UsePreviousAppDir=yes
UsePreviousGroup=yes

; x64 application. The Setup EXE itself stays 32-bit so it can report a clear
; message on an unsupported machine rather than refusing to start.
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

; A running UsageBar is asked to close through this mutex — the same name the
; application creates — instead of being found by process name, which could
; match something unrelated. Inno prompts with retry/cancel; nothing is killed.
AppMutex=Local\UsageBar.Windows.SingleInstance
CloseApplications=yes
CloseApplicationsFilter=*.exe
RestartApplications=no
RestartIfNeededByRun=no

Uninstallable=yes
UninstallDisplayName={#AppName}
UninstallDisplayIcon={app}\{#AppExeName}
SetupIconFile={#SourcePath}\UsageBar.ico
WizardStyle=modern
Compression=lzma2/max
SolidCompression=yes
OutputDir={#OutputDir}
OutputBaseFilename=UsageBar-Setup-x64
; No license page: UsageBar ships no click-through agreement, so the wizard does
; not manufacture one.
LicenseFile=
; The application is a tray app with no main window; nothing here should imply
; a reboot is involved.
AlwaysRestart=no

[Languages]
Name: "en"; MessagesFile: "compiler:Default.isl"
Name: "tr"; MessagesFile: "compiler:Languages\Turkish.isl"

[CustomMessages]
en.LaunchAfterInstall=Launch %1
en.CreateDesktopIcon=Create a &desktop shortcut
tr.LaunchAfterInstall=%1 uygulamasını başlat
tr.CreateDesktopIcon=&Masaüstü kısayolu oluştur

[Tasks]
; Unchecked by default: a tray application does not need a desktop icon.
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
; The entire verified staging payload, exactly as the portable ZIP contains it.
Source: "{#PayloadDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExeName}"; IconFilename: "{app}\{#AppExeName}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExeName}"; IconFilename: "{app}\{#AppExeName}"; Tasks: desktopicon

[Run]
; Checked by default, and run unelevated as the interactive user. nowait because
; UsageBar is a tray application: it never opens a main window, so waiting for
; one would look like a hung install.
Filename: "{app}\{#AppExeName}"; Description: "{cm:LaunchAfterInstall,{#AppName}}"; Flags: nowait postinstall skipifsilent

; Nothing else runs. UsageBar's autostart preference lives in HKCU and is owned
; by the application, so the installer neither creates nor removes a Run entry,
; a Startup shortcut or a scheduled task.

[UninstallDelete]
; Only files the installer itself created outside [Files] would belong here, and
; there are none. Settings and usage history live in %LOCALAPPDATA%\UsageBar,
; which is deliberately untouched so an uninstall — or an upgrade — never
; discards the user's data.
