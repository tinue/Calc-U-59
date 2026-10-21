; Inno Setup script for the Calc-U-59 Windows installer, run by
; .github/workflows/build.yml after windeployqt has staged Qt6/dist.
; /DAPP_ARCH=arm64 builds the ARM64 installer; the default is x64.
; The version comes from the CMake build (Qt6/build/generated/Version.iss,
; itself from the Xcode project's MARKETING_VERSION).

#ifndef APP_ARCH
  #define APP_ARCH "x64"
#endif

#include "..\..\build\generated\Version.iss"

[Setup]
AppName=Calc-U-59
AppVersion={#APP_VERSION}
AppPublisher=Martin Erzberger
AppPublisherURL=https://github.com/tinue/Calc-U-59
DefaultDirName={autopf}\Calc-U-59
DefaultGroupName=Calc-U-59
UninstallDisplayIcon={app}\Calc-U-59.exe
LicenseFile=..\..\..\LICENSE
#if APP_ARCH == "arm64"
  OutputBaseFilename=Calc-U-59-Setup-arm64
  ArchitecturesInstallIn64BitMode=arm64
  ArchitecturesAllowed=arm64
#else
  OutputBaseFilename=Calc-U-59-Setup
  ArchitecturesInstallIn64BitMode=x64compatible
  ArchitecturesAllowed=x64compatible
#endif
OutputDir=..\..\..
Compression=lzma2
SolidCompression=yes
ChangesAssociations=yes

[Files]
Source: "..\..\dist\*"; DestDir: "{app}"; Flags: recursesubdirs ignoreversion

[Run]
; windeployqt --compiler-runtime places the matching VC++ redistributable here.
Filename: "{app}\vc_redist.x64.exe"; Parameters: "/install /quiet /norestart"; StatusMsg: "Installing Visual C++ Redistributable..."; Check: FileExists(ExpandConstant('{app}\vc_redist.x64.exe')); Flags: waituntilterminated
Filename: "{app}\vc_redist.arm64.exe"; Parameters: "/install /quiet /norestart"; StatusMsg: "Installing Visual C++ Redistributable..."; Check: FileExists(ExpandConstant('{app}\vc_redist.arm64.exe')); Flags: waituntilterminated
Filename: "{app}\Calc-U-59.exe"; Description: "Start Calc-U-59"; Flags: nowait postinstall skipifsilent

[Registry]
; Open .ti59 / .ti58 / .ti58c state files with Calc-U-59.
Root: HKA; Subkey: "Software\Classes\.ti59"; ValueType: string; ValueData: "CalcU59.StateFile"; Flags: uninsdeletevalue
Root: HKA; Subkey: "Software\Classes\.ti58"; ValueType: string; ValueData: "CalcU59.StateFile"; Flags: uninsdeletevalue
Root: HKA; Subkey: "Software\Classes\.ti58c"; ValueType: string; ValueData: "CalcU59.StateFile"; Flags: uninsdeletevalue
Root: HKA; Subkey: "Software\Classes\CalcU59.StateFile"; ValueType: string; ValueData: "Calc-U-59 State File"; Flags: uninsdeletekey
Root: HKA; Subkey: "Software\Classes\CalcU59.StateFile\DefaultIcon"; ValueType: string; ValueData: "{app}\Calc-U-59.exe,0"
Root: HKA; Subkey: "Software\Classes\CalcU59.StateFile\shell\open\command"; ValueType: string; ValueData: """{app}\Calc-U-59.exe"" ""%1"""

[Icons]
Name: "{group}\Calc-U-59"; Filename: "{app}\Calc-U-59.exe"
Name: "{group}\Uninstall Calc-U-59"; Filename: "{uninstallexe}"
Name: "{commondesktop}\Calc-U-59"; Filename: "{app}\Calc-U-59.exe"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop icon"; GroupDescription: "Additional icons:"; Flags: unchecked
