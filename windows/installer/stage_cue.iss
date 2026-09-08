; Stage Cue — script Inno Setup.
;
; Installation par utilisateur (pas d'élévation UAC) : condition pour que la
; réinstallation silencieuse déclenchée par l'app elle-même (voir
; lib/core/update/app_update_installer.dart) ne fasse jamais apparaître de
; prompt Windows.
;
; L'AppMutex ci-dessous doit correspondre EXACTEMENT à `kAppMutexName` dans
; lib/core/update/app_mutex_windows.dart — c'est ce qui permet à Inno Setup de
; détecter l'instance en cours, la fermer proprement, puis la relancer après
; installation (CloseApplications / RestartApplications), sans que l'app ait
; à orchestrer elle-même sa propre fermeture.
;
; MyAppVersion est injecté depuis la CI : ISCC.exe /DMyAppVersion=X.Y.Z
#define MyAppName "Stage Cue"
#define MyAppPublisher "Armand Ribault"
#define MyAppExeName "stage_cue.exe"
#define MyAppMutex "StageCueAppMutex"
#ifndef MyAppVersion
  #define MyAppVersion "0.0.0"
#endif

[Setup]
AppId={{0E1CB79D-155B-4778-88A7-96D18A386966}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={localappdata}\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
OutputBaseFilename=StageCue-Setup-{#MyAppVersion}
OutputDir=installer_output
Compression=lzma2
SolidCompression=yes
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
AppMutex={#MyAppMutex}
CloseApplications=force
RestartApplications=yes
WizardStyle=modern

[Languages]
Name: "french"; MessagesFile: "compiler:Languages\French.isl"

[Files]
Source: "..\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: recursesubdirs ignoreversion

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "Créer un raccourci sur le Bureau"; Flags: unchecked

[Run]
; `skipifsilent` : en installation silencieuse (mise à jour auto-déclenchée
; par l'app), c'est RestartApplications qui relance l'instance déjà fermée —
; cette entrée ne sert qu'à proposer le lancement après une install manuelle.
Filename: "{app}\{#MyAppExeName}"; Description: "Lancer {#MyAppName}"; Flags: nowait postinstall skipifsilent
