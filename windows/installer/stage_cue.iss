; Stage Cue — script Inno Setup.
;
; Installation par utilisateur (pas d'élévation UAC) : condition pour que la
; réinstallation silencieuse déclenchée par l'app elle-même (voir
; lib/core/update/app_update_installer.dart) ne fasse jamais apparaître de
; prompt Windows.
;
; Pas d'`AppMutex` : en /SUPPRESSMSGBOXES, Inno répond « Annuler » à la boîte
; « l'application est en cours d'exécution » et abandonne l'installation sans
; rien afficher (code de sortie 1), avant même `CloseApplications`. L'app se
; ferme donc elle-même après avoir lancé l'installeur ; si elle tient encore
; des fichiers, le Restart Manager (`CloseApplications=force`) la ferme. La
; relance est une entrée [Run] explicite (ADR 0037).
;
; MyAppVersion est injecté depuis la CI : ISCC.exe /DMyAppVersion=X.Y.Z
#define MyAppName "Stage Cue"
#define MyAppPublisher "Armand Ribault"
#define MyAppExeName "stage_cue.exe"
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
CloseApplications=force
RestartApplications=no
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
; Installation manuelle : proposer le lancement à la fin de l'assistant.
Filename: "{app}\{#MyAppExeName}"; Description: "Lancer {#MyAppName}"; Flags: nowait postinstall skipifsilent
; Mise à jour silencieuse (lancée par l'app, qui s'est fermée) : relance explicite.
Filename: "{app}\{#MyAppExeName}"; Flags: nowait skipifnotsilent
