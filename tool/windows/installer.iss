; Inno Setup script for the Windows version of Quiz me.
; Built in CI:  iscc /DAppVersion=1.0.0 /DSourceDir=<Release folder> /O<out> tool\windows\installer.iss
; Installs per user (no administrator prompt). Learning data lives in
; %APPDATA%\Rady Radwan\Quiz me and is kept on update and uninstall.

#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif
#ifndef SourceDir
  #define SourceDir "..\..\build\windows\x64\runner\Release"
#endif

[Setup]
AppId={{8F2B6C41-3D7A-4E59-9A61-2C7E5B0D4F13}
AppName=Quiz me
AppVersion={#AppVersion}
AppVerName=Quiz me {#AppVersion}
AppPublisher=Rady Radwan
AppPublisherURL=https://github.com/rady-radwan/quizzme
DefaultDirName={autopf}\Quiz me
DefaultGroupName=Quiz me
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
OutputBaseFilename=QuizMe-Setup
SetupIconFile=..\branding\app_icon.ico
UninstallDisplayIcon={app}\QuizMe.exe
UninstallDisplayName=Quiz me
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
CloseApplications=yes
RestartApplications=no

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\Quiz me"; Filename: "{app}\QuizMe.exe"
Name: "{autodesktop}\Quiz me"; Filename: "{app}\QuizMe.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\QuizMe.exe"; Description: "{cm:LaunchProgram,Quiz me}"; Flags: nowait postinstall skipifsilent
