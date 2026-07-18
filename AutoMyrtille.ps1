param(
    [switch]$Install,
    [switch]$Uninstall,
    [switch]$NoReboot,
    [switch]$SslCert,
    [string]$Domain
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$MyrtilleVersion = 'v2.9.2'
$MsiUrl = "https://github.com/cedrozor/myrtille/releases/download/$MyrtilleVersion/Myrtille_2.9.2_x86_x64_Setup.msi"
$InstallDir = 'C:\Program Files\Myrtille'
$TempDir = "$env:TEMP\AutoMyrtille"
$PoolName = 'RDPWebPool'
$AppName = 'rdpweb'
$SvcName = 'Myrtille.Services'
$SvcPath = "$InstallDir\bin\Myrtille.Services.exe"
$StateFile = "$env:SystemDrive\AutoMyrtille_InstallState.json"
$HttpPort = 11111
$HttpsPort = 12345
$ProxyPrefix = 'https://ghproxy.net/'

function Write-Info  { Write-Host '[*] ' ($args[0]) -ForegroundColor Cyan }
function Write-Ok    { Write-Host '[+] ' ($args[0]) -ForegroundColor Green }
function Write-Warn  { Write-Host '[!] ' ($args[0]) -ForegroundColor Yellow }
function Write-Fail  { Write-Host '[-] ' ($args[0]) -ForegroundColor Red }

function Read-Choice($Prompt, $Default) {
    $input = Read-Host $Prompt
    if ([string]::IsNullOrWhiteSpace($input)) { return $Default }
    return $input.Trim()
}

function Read-YesNo($Prompt, $DefaultYes) {
    $s = if ($DefaultYes) { 'Y/n' } else { 'y/N' }
    $input = Read-Host "$Prompt [$s]"
    if ([string]::IsNullOrWhiteSpace($input)) { return $DefaultYes }
    return $input -eq 'y' -or $input -eq 'Y'
}

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p = New-Object Security.Principal.WindowsPrincipal($id)
    if (-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Fail '必须以管理员身份运行'
        exit 1
    }
}

function Test-WindowsEdition {
    $edition = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').EditionID
    if ($edition -match 'Home|Core|Cloud') {
        Write-Fail 'Windows 家庭版不含 IIS，无法安装 Myrtille'
        Write-Info  '请使用 Windows 专业版/企业版/教育版 或 Windows Server'
        exit 1
    }
    Write-Ok "Windows 版本: $edition"
}

function Test-DotNet {
    try {
        $release = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full' -ErrorAction Stop).Release
        if ($release -ge 378389) {
            Write-Ok ".NET Framework 4.5+ 已安装 (Release: $release)"
            return
        }
    } catch {}
    Write-Info '正在安装 .NET Framework 4.8...'
    $url = $ProxyPrefix + 'https://raw.githubusercontent.com/lcxxjmsg-cyber/AutoMyrtille/main/plug/dotNetFx45_Full_setup.exe'
    $out = "$TempDir\ndp48.exe"
    try { Invoke-WebRequest -Uri $url -OutFile $out -UseBasicParsing }
    catch { Write-Fail "下载失败: $_"; exit 1 }
    $proc = Start-Process -FilePath $out -ArgumentList '/q /norestart' -Wait -PassThru -NoNewWindow
    if ($proc.ExitCode -ne 0 -and $proc.ExitCode -ne 3010) {
        Write-Fail ".NET 安装失败 (ExitCode: $($proc.ExitCode))"
        exit 1
    }
    Write-Ok '.NET Framework 4.8 安装完成'
}

function Enable-WindowsFeatures {
    $features = @(
        'IIS-WebServerRole','IIS-WebServer','IIS-CommonHttpFeatures',
        'IIS-DefaultDocument','IIS-HttpErrors','IIS-StaticContent',
        'IIS-HealthAndDiagnostics','IIS-HttpLogging',
        'IIS-HttpCompressionStatic','IIS-RequestFiltering',
        'IIS-ApplicationDevelopment','IIS-ISAPIExtensions',
        'IIS-ISAPIFilter','IIS-WebSockets',
        'IIS-ManagementConsole','IIS-ManagementScriptingTools',
        'IIS-NetFxExtensibility45','IIS-ASPNET45',
        'WAS-WindowsActivationService','WAS-ProcessModel','WAS-ConfigurationAPI',
        'WCF-HTTP-Activation45'
    )
    $needReboot = $false
    foreach ($f in $features) {
        $state = (Get-WindowsOptionalFeature -Online -FeatureName $f -ErrorAction SilentlyContinue).State
        if ($state -ne 'Enabled') {
            Write-Info "正在启用: $f"
            try {
                $result = Enable-WindowsOptionalFeature -Online -FeatureName $f -All -LimitAccess -Source @('C:\Windows\WinSxS') -NoRestart -ErrorAction Stop
                if ($result.RestartNeeded -or $result.RestartRequired) { $needReboot = $true }
            } catch {
                try {
                    $result = Enable-WindowsOptionalFeature -Online -FeatureName $f -All -NoRestart -ErrorAction Stop
                    if ($result.RestartNeeded -or $result.RestartRequired) { $needReboot = $true }
                } catch { Write-Fail "启用失败: $_"; exit 1 }
            }
        }
    }
    if ($needReboot) {
        Write-Warn '需要重启以完成 IIS 功能安装'
        if ($NoReboot) {
            Write-Warn '请手动重启后重新运行安装'
            exit 0
        }
        $state = @{Step=5; UseSsl=$script:UseSsl; CertDomain=$script:CertDomain; HttpPort=$script:HttpPort; HttpsPort=$script:HttpsPort}
        $state | ConvertTo-Json | Out-File $StateFile -Encoding UTF8
        Write-Info '重启后将自动继续安装...'
        Write-Info '10 秒后重启...'
        Start-Sleep 10
        Restart-Computer -Force
        exit 0
    }
    Write-Ok 'Windows 功能已启用'
}

function Resolve-MsiSourceDir {
    param($MsiPath, $ExtractTo)
    Write-Info '正在提取安装文件...'
    $proc = Start-Process -FilePath 'msiexec.exe' -ArgumentList "/a `"$MsiPath`" /qn TARGETDIR=`"$ExtractTo`"" -Wait -PassThru -NoNewWindow
    if ($proc.ExitCode -ne 0) {
        Write-Fail "MSI 提取失败: $($proc.ExitCode)"
        exit 1
    }
    $found = Get-ChildItem -Path $ExtractTo -Recurse -Filter 'Myrtille.Services.exe' -File -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($found) { return $found.DirectoryName.Replace('\bin','') }
    $found2 = Get-ChildItem -Path $ExtractTo -Recurse -Filter 'Default.aspx' -File -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($found2) { return $found2.DirectoryName }
    return $ExtractTo
}

function Install-MyrtilleFiles {
    $msiPath = "$TempDir\Myrtille.msi"
    $extractRoot = "$TempDir\Extract"
    if (-not (Test-Path $msiPath)) {
        $downloadUrl = "$ProxyPrefix$MsiUrl"
        Write-Info "正在下载 Myrtille $MyrtilleVersion ..."
        try { Invoke-WebRequest -Uri $downloadUrl -OutFile $msiPath -UseBasicParsing }
        catch { Write-Fail "下载失败"; Write-Info "手动下载: $MsiUrl"; exit 1 }
        $size = (Get-Item $msiPath).Length / 1MB -as [int]
        Write-Ok "下载完成: ${size} MB"
    } else { Write-Info '使用本地安装包' }
    if (Test-Path $extractRoot) { Remove-Item -Recurse -Force $extractRoot }
    New-Item -ItemType Directory -Path $extractRoot -Force | Out-Null
    $sourceDir = Resolve-MsiSourceDir -MsiPath $msiPath -ExtractTo $extractRoot
    if (Test-Path $InstallDir) {
        $backupDir = "$InstallDir.backup.$(Get-Date -Format yyyyMMddHHmmss)"
        Move-Item -Path $InstallDir -Destination $backupDir -Force
        Write-Info "旧目录已备份到 $backupDir"
    }
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
    Get-ChildItem -Path $sourceDir | ForEach-Object {
        if ($_.PSIsContainer) { Copy-Item -Path $_.FullName -Destination "$InstallDir\$($_.Name)" -Recurse -Force }
        else { Copy-Item -Path $_.FullName -Destination $InstallDir -Force }
    }
    New-Item -ItemType Directory -Path "$InstallDir\log" -Force | Out-Null
    New-Item -ItemType Directory -Path "$InstallDir\data" -Force | Out-Null
    if (-not (Test-Path $SvcPath)) { Write-Fail '未找到核心组件，部署失败'; exit 1 }
    Write-Ok '文件部署完成'
}

function Configure-IIS {
    try { Import-Module WebAdministration -ErrorAction Stop; $null = Get-ChildItem 'IIS:\Sites' -ErrorAction Stop }
    catch { Write-Fail 'IIS 模块不可用，可能需要重启'; exit 1 }
    try {
        $site = Get-Website 'Default Web Site'
        if (-not $site) { New-Website -Name 'Default Web Site' -Port $script:HttpPort -PhysicalPath "$env:SystemDrive\inetpub\wwwroot" }
        else {
            $hasBinding = $site.Bindings.Collection | Where-Object { $_.protocol -eq 'http' -and $_.bindingInformation -like "*:$($script:HttpPort):*" }
            if (-not $hasBinding) { New-WebBinding -Name 'Default Web Site' -IPAddress '*' -Port $script:HttpPort -Protocol 'http' }
            if ($site.State -ne 'Started') { Start-Website 'Default Web Site' }
        }
    } catch { Write-Fail "IIS 站点配置失败: $_"; exit 1 }
    $pool = Get-Item "IIS:\AppPools\$PoolName" -ErrorAction SilentlyContinue
    if ($pool) { Stop-WebAppPool -Name $PoolName -ErrorAction SilentlyContinue; Remove-WebAppPool -Name $PoolName }
    Write-Info '正在创建应用池...'
    New-WebAppPool -Name $PoolName
    Set-ItemProperty "IIS:\AppPools\$PoolName" managedRuntimeVersion 'v4.0'
    Set-ItemProperty "IIS:\AppPools\$PoolName" managedPipelineMode Classic
    Set-ItemProperty "IIS:\AppPools\$PoolName" processModel.loadUserProfile $true
    Set-ItemProperty "IIS:\AppPools\$PoolName" processModel.idleTimeout ([TimeSpan]::Zero)
    Set-ItemProperty "IIS:\AppPools\$PoolName" recycling.periodicRestart.time ([TimeSpan]::Zero)
    $existing = Get-WebApplication -Site 'Default Web Site' -Name $AppName -ErrorAction SilentlyContinue
    if ($existing) { Remove-WebApplication -Site 'Default Web Site' -Name $AppName }
    New-WebApplication -Site 'Default Web Site' -Name $AppName -PhysicalPath $InstallDir -ApplicationPool $PoolName
    Set-WebConfigurationProperty -Filter 'system.webServer/webSocket' -Name 'enabled' -Value $true -PSPath "IIS:\Sites\Default Web Site\$AppName"
    $appPoolUser = "IIS AppPool\$PoolName"
    try {
        $acl = Get-Acl "$InstallDir\log"
        $rule = New-Object System.Security.AccessControl.FileSystemAccessRule($appPoolUser,'FullControl','ContainerInherit,ObjectInherit','None','Allow')
        $acl.SetAccessRule($rule); Set-Acl -Path "$InstallDir\log" -AclObject $acl
    } catch { }
    Write-Ok 'IIS 配置完成'
}

function Register-Services {
    if (-not (Test-Path $SvcPath)) { Write-Fail '服务程序不存在'; exit 1 }
    $existing = Get-Service -Name $SvcName -ErrorAction SilentlyContinue
    if ($existing) {
        Stop-Service -Name $SvcName -Force -ErrorAction SilentlyContinue; Start-Sleep 2
        Start-Process -FilePath 'sc.exe' -ArgumentList "delete $SvcName" -Wait -NoNewWindow; Start-Sleep 2
    }
    Write-Info '正在注册服务...'
    $proc = Start-Process -FilePath 'sc.exe' -ArgumentList "create $SvcName displayname= $SvcName binpath= `"$SvcPath`" start= auto" -Wait -PassThru -NoNewWindow
    if ($proc.ExitCode -ne 0) {
        Write-Warn 'sc.exe 失败，尝试 InstallUtil...'
        $util = if (Test-Path "$env:SystemRoot\Microsoft.NET\Framework64\v4.0.30319\InstallUtil.exe") {
            "$env:SystemRoot\Microsoft.NET\Framework64\v4.0.30319\InstallUtil.exe"
        } else { "$env:SystemRoot\Microsoft.NET\Framework\v4.0.30319\InstallUtil.exe" }
        Start-Process -FilePath $util -ArgumentList "`"$SvcPath`"" -Wait -NoNewWindow
    }
    Write-Ok "服务 $SvcName 已注册"
}

function Configure-Firewall {
    $rules = @(@{Name='RDPWeb-HTTP'; Port=$script:HttpPort; Proto='TCP'})
    if ($script:UseSsl) { $rules += @{Name='RDPWeb-HTTPS'; Port=$script:HttpsPort; Proto='TCP'} }
    foreach ($r in $rules) {
        if (-not (Get-NetFirewallRule -DisplayName $r.Name -ErrorAction SilentlyContinue)) {
            New-NetFirewallRule -DisplayName $r.Name -Direction Inbound -LocalPort $r.Port -Protocol $r.Proto -Action Allow -Profile Any | Out-Null
        }
    }
    Write-Ok '防火墙已配置'
}

function Configure-SelfSignedCert {
    $hostname = if ($script:CertDomain) { $script:CertDomain } else { ([System.Net.Dns]::GetHostByName($env:computerName)).HostName }
    Write-Info "正在创建自签名证书 (域名: $hostname)..."
    $existing = Get-ChildItem 'Cert:\LocalMachine\My' | Where-Object { $_.DnsNameList -contains $hostname }
    if ($existing) { $cert = $existing | Select-Object -First 1; Write-Info '使用已有证书' }
    else { $cert = New-SelfSignedCertificate -CertStoreLocation 'Cert:\LocalMachine\My' -DnsName $hostname -FriendlyName 'Myrtille self-signed certificate' }
    if (-not $cert) { Write-Fail '证书创建失败'; exit 1 }

    $port = $script:HttpsPort
    $httpsBinding = Get-WebBinding -Name 'Default Web Site' -Protocol 'https' | Where-Object { ($_.bindingInformation -split ':')[1] -eq "$port" }
    if (-not $httpsBinding) {
        New-WebBinding -Name 'Default Web Site' -IPAddress '*' -Port $port -Protocol 'https'
        Start-Sleep 2
        $httpsBinding = Get-WebBinding -Name 'Default Web Site' -Protocol 'https' | Where-Object { ($_.bindingInformation -split ':')[1] -eq "$port" }
    }
    if (-not $httpsBinding) { Write-Fail "HTTPS 端口 $port 绑定创建失败"; exit 1 }

    $certHash = $cert.GetCertHashString()
    $httpsBinding.AddSslCertificate($certHash, 'my')
    Write-Ok 'HTTPS 自签名证书已配置'
}


function Import-RdpSettings {
    @(
        @{Path='HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services'; Name='fAllowUnlistedRemotePrograms'; Value=1}
        @{Path='HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server'; Name='fDenyTSConnections'; Value=0}
        @{Path='HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server'; Name='fSingleSessionPerUser'; Value=0}
        @{Path='HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp'; Name='UserAuthentication'; Value=0}
    ) | ForEach-Object {
        if (-not (Test-Path $_.Path)) { New-Item -Path $_.Path -Force | Out-Null }
        Set-ItemProperty -Path $_.Path -Name $_.Name -Value $_.Value -Type DWord -Force
    }
    Write-Ok 'RDP 配置已应用'
}

function Start-MyrtilleServices {
    for ($i = 0; $i -lt 20; $i++) {
        $svc = Get-Service -Name $SvcName -ErrorAction SilentlyContinue
        if (-not $svc) { Start-Sleep 3; continue }
        if ($svc.Status -eq 'Stopped') {
            try { Start-Service -Name $SvcName -ErrorAction Stop; Start-Sleep 3; $svc = Get-Service -Name $SvcName; if ($svc.Status -eq 'Running') { Write-Ok '服务已启动'; return } } catch { Start-Sleep 3 }
        } elseif ($svc.Status -eq 'Running') { Write-Ok '服务已在运行'; return }
    }
    Write-Warn '服务未启动，请手动检查 services.msc'
}

function Show-Summary {
    $ip = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -notmatch 'Loopback|Bluetooth|VMware|Virtual|Hyper-V|vEthernet' -and $_.IPAddress -ne '127.0.0.1' } | Select-Object -First 1).IPAddress
    $p = if ($script:UseSsl) { 'https' } else { 'http' }
    $portSuffix = if ($script:UseSsl) { ":$($script:HttpsPort)" } else { ":$($script:HttpPort)" }
    $exampleServer = if ($script:CertDomain) { $script:CertDomain } elseif ($ip) { $ip } else { '127.0.0.1' }
    Write-Host ''
    Write-Host '=============================================' -ForegroundColor Green
    Write-Host " Myrtille $MyrtilleVersion 部署成功" -ForegroundColor Green
    Write-Host '=============================================' -ForegroundColor Green
    Write-Host ''
    Write-Host ' Web 访问地址:' -ForegroundColor Yellow
    Write-Host " 本机: ${p}://127.0.0.1${portSuffix}/$AppName" -ForegroundColor White
    if ($ip) { Write-Host " 局域网: ${p}://$ip${portSuffix}/$AppName" -ForegroundColor White }
    Write-Host " 主机名: ${p}://$env:COMPUTERNAME${portSuffix}/$AppName" -ForegroundColor White
    if ($script:CertDomain) { Write-Host " 域名: ${p}://$($script:CertDomain)${portSuffix}/$AppName" -ForegroundColor White }
    Write-Host ''
    Write-Host " 安装路径: $InstallDir" -ForegroundColor Gray
    Write-Host ' Windows 服务: Myrtille.Services (自动启动)' -ForegroundColor Gray
    Write-Host " HTTP 端口: $($script:HttpPort)" -ForegroundColor Gray
    if ($script:UseSsl) { Write-Host " HTTPS 端口: $($script:HttpsPort)" -ForegroundColor Gray }
    Write-Host ''
    Write-Host ' URL 访问方式（三级跳过）:' -ForegroundColor Cyan
    Write-Host ' ① 手动登录（需填服务器/账号/密码）' -ForegroundColor Gray
    Write-Host "    ${p}://127.0.0.1${portSuffix}/$AppName" -ForegroundColor White
    Write-Host " ② 直连（指定服务器，仍需填账号密码）" -ForegroundColor Gray
    Write-Host "    ${p}://127.0.0.1${portSuffix}/$AppName/?server=$exampleServer&connect=Connect%21" -ForegroundColor White
    Write-Host ' ③ 全自动直连（直达桌面）' -ForegroundColor Gray
    Write-Host "    ${p}://127.0.0.1${portSuffix}/$AppName/?server=$exampleServer&user=USERNAME&password=PASSWORD&width=1920&height=1080&connect=Connect%21" -ForegroundColor White
    Write-Host ''
    Write-Host ' 提示:' -ForegroundColor Yellow
    Write-Host ' 如果目标 RDP 端口不是 3389，在 server= 后加端口，如 server=192.168.1.100:3390' -ForegroundColor Gray
    Write-Host ' 域名 (domain) 仅企业 AD 环境需要，家庭电脑可留空' -ForegroundColor Gray
    Write-Host ' 参数值需要 URL 编码（中文/特殊字符），可用在线工具编码' -ForegroundColor Gray
    Write-Host ''
    Write-Host ' 使用前请确保目标机已启用远程桌面' -ForegroundColor Yellow
    Write-Host '=============================================' -ForegroundColor Green
}

function Uninstall-Myrtille {
    Write-Info '===== 开始卸载 Myrtille ====='
    $svc = Get-Service -Name $SvcName -ErrorAction SilentlyContinue
    if ($svc) {
        Write-Info '正在停止并删除服务...'
        Stop-Service -Name $SvcName -Force -ErrorAction SilentlyContinue; Start-Sleep 2
        Start-Process -FilePath 'sc.exe' -ArgumentList "delete $SvcName" -Wait -NoNewWindow
        Write-Ok '服务已删除'
    }
    try {
        Import-Module WebAdministration -ErrorAction SilentlyContinue
        $app = Get-WebApplication -Site 'Default Web Site' -Name $AppName -ErrorAction SilentlyContinue
        if ($app) { Remove-WebApplication -Site 'Default Web Site' -Name $AppName; Write-Ok 'Web 应用已删除' }
        $pool = Get-Item "IIS:\AppPools\$PoolName" -ErrorAction SilentlyContinue
        if ($pool) { Stop-WebAppPool -Name $PoolName -ErrorAction SilentlyContinue; Remove-WebAppPool -Name $PoolName; Write-Ok '应用池已删除' }
        $httpsBinding = Get-WebBinding -Name 'Default Web Site' -Protocol 'https' -ErrorAction SilentlyContinue
        if ($httpsBinding) { Remove-WebBinding -InputObject $httpsBinding; Write-Ok 'HTTPS 绑定已删除' }
    } catch { Write-Warn "IIS 清理部分失败: $_" }
    @('RDPWeb-HTTP', 'RDPWeb-HTTPS') | ForEach-Object {
        $rule = Get-NetFirewallRule -DisplayName $_ -ErrorAction SilentlyContinue
        if ($rule) { Remove-NetFirewallRule -DisplayName $_; Write-Ok "防火墙规则已删除: $_" }
    }
    $certs = Get-ChildItem 'Cert:\LocalMachine\My' | Where-Object { $_.FriendlyName -eq 'Myrtille self-signed certificate' }
    foreach ($cert in $certs) {
        try {
            $store = New-Object System.Security.Cryptography.X509Certificates.X509Store('My','LocalMachine')
            $store.Open('ReadWrite'); $store.Remove($cert); $store.Close()
            Write-Ok '证书已删除'
        } catch { Write-Warn "证书删除失败: $_" }
    }
    if (Test-Path $InstallDir) { Remove-Item -Recurse -Force $InstallDir -ErrorAction SilentlyContinue; Write-Ok '安装目录已删除' }
    Get-ChildItem "$env:SystemDrive\Program Files" -Directory -Filter 'Myrtille.backup.*' -ErrorAction SilentlyContinue | ForEach-Object { Remove-Item -Recurse -Force $_.FullName -ErrorAction SilentlyContinue }
    if (Test-Path $StateFile) { Remove-Item -Force $StateFile -ErrorAction SilentlyContinue }
    Write-Ok '===== Myrtille 已完全卸载 ====='
}

function Test-Installed {
    if (-not (Test-Path $InstallDir)) { return $false }
    if (-not (Test-Path "$InstallDir\install.json")) { return $false }
    return $true
}

function Show-ConnectionInfo {
    $cfg = Get-Content "$InstallDir\install.json" -Raw | ConvertFrom-Json
    $p = if ($cfg.UseSsl) { 'https' } else { 'http' }
    $portSuffix = if ($cfg.UseSsl) { ":$($cfg.HttpsPort)" } else { ":$($cfg.HttpPort)" }
    $ip = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -notmatch 'Loopback|Bluetooth|VMware|Virtual|Hyper-V|vEthernet' -and $_.IPAddress -ne '127.0.0.1' } | Select-Object -First 1).IPAddress
    $exampleServer = if ($cfg.CertDomain) { $cfg.CertDomain } elseif ($ip) { $ip } else { '127.0.0.1' }
    Write-Host ''
    Write-Host '=============================================' -ForegroundColor Green
    Write-Host " Myrtille $MyrtilleVersion - 连接信息" -ForegroundColor Green
    Write-Host " 安装时间: $($cfg.InstallTime)" -ForegroundColor Gray
    Write-Host '=============================================' -ForegroundColor Green
    Write-Host ''
    Write-Host ' 访问地址:' -ForegroundColor Yellow
    Write-Host " 本机: ${p}://127.0.0.1${portSuffix}/$AppName" -ForegroundColor White
    if ($ip) { Write-Host " 局域网: ${p}://$ip${portSuffix}/$AppName" -ForegroundColor White }
    Write-Host " 主机名: ${p}://$env:COMPUTERNAME${portSuffix}/$AppName" -ForegroundColor White
    if ($cfg.CertDomain) { Write-Host " 域名: ${p}://$($cfg.CertDomain)${portSuffix}/$AppName" -ForegroundColor White }
    Write-Host ''
    Write-Host ' ② 直连（指定服务器）:' -ForegroundColor Cyan
    Write-Host " ${p}://127.0.0.1${portSuffix}/$AppName/?server=$exampleServer&connect=Connect%21" -ForegroundColor White
    Write-Host ' ③ 全自动直连（直达桌面）:' -ForegroundColor Cyan
    Write-Host " ${p}://127.0.0.1${portSuffix}/$AppName/?server=$exampleServer&user=USERNAME&password=PASSWORD&width=1920&height=1080&connect=Connect%21" -ForegroundColor White
    Write-Host ''
    Write-Host ' 非 3389 RDP 端口: server=IP:端口' -ForegroundColor Gray
    Write-Host ' 域名 (domain) 仅企业 AD 需要，家庭留空' -ForegroundColor Gray
    Write-Host ''
    Write-Host " HTTP 端口: $($cfg.HttpPort)" -ForegroundColor Gray
    if ($cfg.UseSsl) { Write-Host " HTTPS 端口: $($cfg.HttpsPort)" -ForegroundColor Gray }
    Write-Host '=============================================' -ForegroundColor Green
}

function Show-MainMenu {
    Clear-Host
    $installed = Test-Installed
    Write-Host '=============================================' -ForegroundColor Cyan
    Write-Host '     Myrtille 部署工具 v2.9.2' -ForegroundColor Cyan
    Write-Host '=============================================' -ForegroundColor Cyan
    if ($installed) {
        Write-Host ''
        Write-Host ' [已安装] 输入 [i] 查看连接信息' -ForegroundColor Green
    }
    Write-Host ''
    Write-Host '  [1] 安装 Myrtille' -ForegroundColor Yellow
    if ($installed) { Write-Host '  [2] 卸载 Myrtille' -ForegroundColor Yellow }
    else { Write-Host '  [2] 卸载 Myrtille (未安装)' -ForegroundColor Gray }
    Write-Host '  [Q] 退出' -ForegroundColor Yellow
    Write-Host ''
    $prompt = if ($installed) { '请选择 [1/2/I/Q]' } else { '请选择 [1/2/Q]' }
    $default = if ($installed) { 'i' } else { '1' }
    $choice = Read-Choice $prompt $default
    return $choice
}

function Show-InstallMenu {
    Write-Host '---------------------------------------------' -ForegroundColor Gray
    Write-Host '  安装选项（直接回车使用默认值）' -ForegroundColor Cyan
    Write-Host '---------------------------------------------' -ForegroundColor Gray
    Write-Host ''
    $domain = Read-Choice '  域名（留空仅 HTTP，有域名则自动 HTTPS 自签名）' ''
    $script:CertDomain = $null
    $script:UseSsl = $false
    if (-not [string]::IsNullOrWhiteSpace($domain)) {
        $script:CertDomain = $domain.Trim()
        $script:UseSsl = $true
    }
    Write-Host '  无论 HTTP/HTTPS，都需要一个 HTTP 入口端口'
    $input = Read-Choice "  HTTP 端口 [$HttpPort]" $HttpPort
    $script:HttpPort = if ($input -match '^\d+$') { [int]$input } else { $HttpPort }
    if ($script:UseSsl) {
        $input2 = Read-Choice "  HTTPS 端口 [$HttpsPort]" $HttpsPort
        $script:HttpsPort = if ($input2 -match '^\d+$') { [int]$input2 } else { $HttpsPort }
    }
    Write-Host ''
    $script:NoReboot = $true
    Write-Info '配置完成，开始安装...'
    Start-Sleep 1
}

function Install-Myrtille {
    $startTime = Get-Date
    if (Test-Path $StateFile) {
        Write-Info '检测到重启恢复标记，跳过前置检查...'
        try { $state = Get-Content $StateFile -Raw | ConvertFrom-Json; $script:UseSsl = $state.UseSsl; $script:CertDomain = $state.CertDomain; $script:HttpPort = $state.HttpPort; $script:HttpsPort = $state.HttpsPort } catch { }
        Remove-Item -Force $StateFile -ErrorAction SilentlyContinue
    } else {
        if (Test-Path $TempDir) { Remove-Item -Recurse -Force $TempDir -ErrorAction SilentlyContinue }
        New-Item -ItemType Directory -Path $TempDir -Force | Out-Null
        Write-Info '===== Myrtille 一键部署 ====='
        Write-Info '[1/9] 权限检查...'; Test-Admin
        Write-Info '[2/9] 版本检查...'; Test-WindowsEdition
        Write-Info '[3/9] .NET 检查...'; Test-DotNet
        Write-Info '[4/9] 启用 IIS...'; Enable-WindowsFeatures
    }
    Write-Info '[5/9] 部署文件...'; Install-MyrtilleFiles
    Write-Info '[6/9] 配置 IIS...'; Configure-IIS
    Write-Info '[7/9] 注册服务...'; Register-Services
    Write-Info '[8/9] 防火墙...'; Configure-Firewall
    if ($script:UseSsl) {
        Write-Info '[SSL] 自签名证书...'
        Configure-SelfSignedCert
    }
    Write-Info '[9/9] 启动服务...'; Start-MyrtilleServices
    Write-Info 'RDP 配置...'; Import-RdpSettings
    Show-Summary
    $config = @{HttpPort=$script:HttpPort; HttpsPort=$script:HttpsPort; UseSsl=$script:UseSsl; CertDomain=$script:CertDomain; InstallTime=(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')}
    $config | ConvertTo-Json | Out-File "$InstallDir\install.json" -Encoding UTF8
    Write-Info "总耗时: $(((Get-Date) - $startTime).Minutes) 分 $(((Get-Date) - $startTime).Seconds) 秒"
}

function Main {
    Test-Admin
    if ($Uninstall) { Uninstall-Myrtille; return }
    if ($Install) {
        $script:UseSsl = $SslCert
        $script:CertDomain = if ($Domain) { $Domain } else { $null }
        $script:HttpPort = $HttpPort
        $script:HttpsPort = $HttpsPort
        Install-Myrtille
        return
    }
    do {
        $choice = Show-MainMenu
        switch ($choice) {
            '1' { Show-InstallMenu; Install-Myrtille; Write-Host ''; Write-Info '按 Enter 返回菜单...'; $null = Read-Host }
            '2' { if (Read-YesNo '确定要卸载 Myrtille 吗' $false) { Uninstall-Myrtille }; Write-Host ''; Write-Info '按 Enter 返回菜单...'; $null = Read-Host }
            'i' { Show-ConnectionInfo; Write-Host ''; Write-Info '按 Enter 返回菜单...'; $null = Read-Host }
            'I' { Show-ConnectionInfo; Write-Host ''; Write-Info '按 Enter 返回菜单...'; $null = Read-Host }
            'q' { return }; 'Q' { return }
            default { Write-Warn '无效选择' }
        }
    } while ($true)
}

try { Main } catch { Write-Fail "操作失败: $_"; exit 1 } finally { if (Test-Path $TempDir) { Remove-Item -Recurse -Force $TempDir -ErrorAction SilentlyContinue } }
