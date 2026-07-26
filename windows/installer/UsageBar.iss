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
en.LaunchUnavailable=UsageBar was installed, but its Start Menu shortcut could not be found, so it was not started. Open UsageBar from the Start Menu.
tr.LaunchAfterInstall=%1 uygulamasını başlat
tr.CreateDesktopIcon=&Masaüstü kısayolu oluştur
tr.LaunchUnavailable=UsageBar kuruldu, ancak Başlat menüsü kısayolu bulunamadığı için başlatılmadı. UsageBar'ı Başlat menüsünden açın.

[Tasks]
; Unchecked by default: a tray application does not need a desktop icon.
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
; The entire verified staging payload, exactly as the portable ZIP contains it.
Source: "{#PayloadDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
; WorkingDir matters: the Start Menu shortcut is also what the final page
; launches, and a shortcut with no working directory would start the
; application in whatever directory the shell happened to be using.
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExeName}"; WorkingDir: "{app}"; IconFilename: "{app}\{#AppExeName}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExeName}"; WorkingDir: "{app}"; IconFilename: "{app}\{#AppExeName}"; Tasks: desktopicon

[Run]
; Launches the Start Menu shortcut, not the executable directly.
;
; Physical testing found that an application started straight from Setup
; inherits Setup's process context rather than the shell's, and in that context
; UsageBar failed to find an installed Codex that it located immediately when
; started from the Start Menu — on the same files, with no other difference.
; Going through the shortcut means the very first launch uses exactly the launch
; path every later one does.
;
; shellexec is required because a .lnk is not directly executable, and it also
; means Setup does not wait for the process — right for a tray application that
; never opens a main window. runasoriginaluser is explicit rather than implied.
; Check: skips the entry when the shortcut is somehow absent, so Setup never
; reports a launch that did not happen.
Filename: "{autoprograms}\{#AppName}.lnk"; Description: "{cm:LaunchAfterInstall,{#AppName}}"; Flags: postinstall shellexec skipifsilent runasoriginaluser; Check: LaunchShortcutAvailable

; Nothing else runs. UsageBar's autostart preference lives in HKCU and is owned
; by the application, so the installer neither creates nor removes a Run entry,
; a Startup shortcut or a scheduled task.

[Code]
var
  ShortcutMissing: Boolean;

{ Evaluated once, after the files and icons are in place and before the final
  page. If the shortcut is not there the launch entry is skipped and the user is
  told where to find UsageBar — Setup never falls back to starting the
  executable itself, because that is the context the fix exists to avoid. }
procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then
    ShortcutMissing := not FileExists(ExpandConstant('{autoprograms}\{#AppName}.lnk'));
end;

function LaunchShortcutAvailable: Boolean;
begin
  Result := not ShortcutMissing;
end;

procedure CurPageChanged(CurPageID: Integer);
begin
  if (CurPageID = wpFinished) and ShortcutMissing then
    MsgBox(ExpandConstant('{cm:LaunchUnavailable}'), mbInformation, MB_OK);
end;

[UninstallDelete]
; Only files the installer itself created outside [Files] would belong here, and
; there are none. Settings and usage history live in %LOCALAPPDATA%\UsageBar,
; which is deliberately untouched so an uninstall — or an upgrade — never
; discards the user's data.
