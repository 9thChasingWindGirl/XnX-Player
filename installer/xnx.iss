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
  ResetPage: TInputOptionWizardPage;
  ExistingDataDir: String;

/// The data folder a previous install pointed at, or '' for a fresh install.
///
/// Without this an upgrade silently rewrote data-dir.txt to the default and the
/// app came up empty even though the real config was still on disk.
function ReadExistingDataDir(): String;
var
  Raw: String;
begin
  Result := '';
  if FileExists(ExpandConstant('{app}\data-dir.txt')) then
  begin
    if LoadStringFromFile(ExpandConstant('{app}\data-dir.txt'), Raw) then
      Result := Trim(Raw);
  end;
end;

procedure InitializeWizard;
begin
  ExistingDataDir := ReadExistingDataDir();

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

  // Pre-select where the data already is. The default option was the reason an
  // upgrade looked like it wiped the library: the files were untouched, but the
  // pointer moved out from under them.
  if ExistingDataDir <> '' then
  begin
    if CompareText(ExistingDataDir, ExpandConstant('{app}\userdata')) = 0 then
      DataModePage.Values[1] := True
    else if CompareText(ExistingDataDir, ExpandConstant('{userappdata}\XnX Player')) = 0 then
      DataModePage.Values[0] := True
    else
    begin
      DataModePage.Values[2] := True;
      DataPage.Values[0] := ExistingDataDir;
    end;
  end
  else
    DataModePage.Values[0] := True;

  ResetPage := CreateInputOptionPage(
    DataPage.ID,
    '现有用户数据',
    '是否保留现有配置',
    '检测到现有数据目录：' + ExistingDataDir,
    False, // 非独占：这一项要能取消勾选
    False
  );
  ResetPage.Add('保留现有配置（推荐）');
  ResetPage.Values[0] := True;
end;

function ShouldSkipPage(PageID: Integer): Boolean;
begin
  Result := False;
  // 只有“自定义目录”才进入路径输入页。
  if PageID = DataPage.ID then
    Result := not DataModePage.Values[2];
  // 全新安装没有旧配置可问。
  if PageID = ResetPage.ID then
    Result := ExistingDataDir = '';
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
    // 只有用户明确取消“保留现有配置”时才清空；数据目录本身留着，
    // 截图与更新缓存对全新配置同样有用。
    if (ExistingDataDir <> '') and (ResetPage.Values[0] = False) then
    begin
      DeleteFile(Dir + '\state.json');
      DeleteFile(Dir + '\library.log');
    end;
    SaveStringToFile(
      ExpandConstant('{app}\data-dir.txt'),
      Dir + #13#10,
      False
    );
  end;
end;
