#define AppVersion GetEnv('XNX_APP_VERSION')
#define PayloadDir GetEnv('XNX_PAYLOAD')
#define OutputDir GetEnv('XNX_OUTPUT')
#define LicensePath GetEnv('XNX_LICENSE')
#define InfoPath GetEnv('XNX_INFO')

[Setup]
AppId={{8E3C0C57-6A3F-4C4E-9E6C-3E7A1F2B9D41}
AppName=XnX Player
AppVersion={#AppVersion}
AppVerName=XnX Player {#AppVersion}
AppPublisher=XnX Player
DefaultDirName={localappdata}\Programs\XnX Player
DefaultGroupName=XnX Player
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
OutputDir={#OutputDir}
OutputBaseFilename=XnX-Player-Setup-{#AppVersion}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
LicenseFile={#LicensePath}
InfoBeforeFile={#InfoPath}
UninstallDisplayIcon={app}\xnx_player.exe
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

[Tasks]
Name: "desktopicon"; Description: "创建桌面快捷方式"; GroupDescription: "附加任务："; Flags: unchecked

[Files]
Source: "{#PayloadDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\XnX Player"; Filename: "{app}\xnx_player.exe"
Name: "{autodesktop}\XnX Player"; Filename: "{app}\xnx_player.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\xnx_player.exe"; Description: "启动 XnX Player"; Flags: nowait postinstall skipifsilent

[Code]
var
  DataModePage: TInputOptionWizardPage;
  DataPage: TInputDirWizardPage;

procedure InitializeWizard;
begin
  DataModePage := CreateInputOptionPage(
    wpSelectDir,
    '数据存放位置',
    '选择用户数据的保存方式',
    'state.json、日志、截图和片头片尾标记会保存在数据目录。更新和卸载不会删除它。',
    True,
    False
  );
  DataModePage.Add('默认位置（%APPDATA%\XnX Player）');
  DataModePage.Add('程序目录下的 userdata 文件夹（便携式）');
  DataModePage.Add('自定义目录');
  DataModePage.Values[0] := True;

  DataPage := CreateInputDirPage(
    DataModePage.ID,
    '自定义数据目录',
    '选择用户数据目录',
    '只在选择“自定义目录”时需要填写。',
    False,
    ''
  );
  DataPage.Add('数据目录：');
  DataPage.Values[0] := ExpandConstant('{userappdata}\XnX Player');
end;

function ShouldSkipPage(PageID: Integer): Boolean;
begin
  Result := False;
  // 只有“自定义目录”才进入路径输入页。
  if PageID = DataPage.ID then
    Result := not DataModePage.Values[2];
end;

function DataDir(): String;
begin
  if DataModePage.Values[1] then
    Result := ExpandConstant('{app}\userdata')
  else if DataModePage.Values[2] then
    Result := Trim(DataPage.Values[0])
  else
    Result := ExpandConstant('{userappdata}\XnX Player');
end;

function NextButtonClick(CurPageID: Integer): Boolean;
begin
  Result := True;
  if CurPageID = DataPage.ID then
  begin
    if Trim(DataPage.Values[0]) = '' then
    begin
      MsgBox('请选择数据目录。', mbError, MB_OK);
      Result := False;
      Exit;
    end;
    if CompareText(DataPage.Values[0], ExpandConstant('{app}')) = 0 then
    begin
      MsgBox('数据目录不能等于程序安装目录，请使用程序目录下的 userdata 子目录或其它位置。', mbError, MB_OK);
      Result := False;
    end;
  end;
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  Dir: String;
begin
  if CurStep = ssPostInstall then
  begin
    Dir := DataDir();
    ForceDirectories(Dir);
    SaveStringToFile(
      ExpandConstant('{app}\data-dir.txt'),
      Dir + #13#10,
      False
    );
  end;
end;
