# Runs a list of edge-case tests one after another in the VirtualBox VM. Each case starts from the
# clean snapshot. Usage:  night.ps1 -Cases B1,F1,E1   (default: all)
param([string[]]$Cases = @())
$here = $PSScriptRoot
$hostsBlockGithub = @'
$h = "$env:SystemRoot\System32\drivers\etc\hosts"
Add-Content $h "`n0.0.0.0 github.com`n0.0.0.0 objects.githubusercontent.com`n0.0.0.0 release-assets.githubusercontent.com`n0.0.0.0 raw.githubusercontent.com`n0.0.0.0 codeload.github.com"
ipconfig /flushdns | Out-Null; 'github blocked in hosts'
'@
$all = [ordered]@{
  # a standard (non-admin) account; Windows refuses every administrator request automatically
  'B1-standard-user' = @{ AdminPrep = "Set-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' ConsentPromptBehaviorUser 0 -Type DWord; 'auto-deny elevation for standard users'"; Motw = $true }
  # Hong Kong: Chinese account name (profile path in Chinese), Chinese system locale (code page 950) and formats
  'F1-chinese-hk' = @{ NewUser = '陳大文'; NewUserAdmin = $true; Locale = 'zh-HK'; Motw = $true }
  # Innsbruck: German account name with space and umlauts, German/Austrian locale (decimal comma),
  # Documents moved into OneDrive (as Windows does when OneDrive backup is on)
  'E1-german-onedrive' = @{ NewUser = 'Jürgen Müller'; NewUserAdmin = $true; Locale = 'de-AT'; Motw = $true;
                           UserPrep = '$d = Join-Path $env:USERPROFILE "OneDrive\Dokumente"; New-Item -ItemType Directory -Force $d | Out-Null; Set-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders" Personal $d; [Environment]::GetFolderPath("MyDocuments")' }
  # GitHub blocked (as in mainland China without VPN, or a strict firewall)
  'H1-github-blocked' = @{ AdminPrep = $hostsBlockGithub + "`nAdd-LocalGroupMember -Group Administrators -Member student"; Reboot = $true; Motw = $true }
  # a VPN/proxy app (e.g. Clash) left configured in Windows but not running
  'P1-dead-proxy' = @{ AdminPrep = "Add-LocalGroupMember -Group Administrators -Member student"; Reboot = $true; MaxMin = 30;
                      UserPrep = '$k = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings"; Set-ItemProperty $k ProxyEnable 1 -Type DWord; Set-ItemProperty $k ProxyServer "127.0.0.1:7890"; "proxy set"' }
  # organisation policy forbids scripts (managed laptop)
  'J1-allsigned-policy' = @{ AdminPrep = "New-Item -Force 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell' | Out-Null; Set-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell' EnableScripts 1 -Type DWord; Set-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell' ExecutionPolicy AllSigned; 'AllSigned policy set'"; MaxMin = 20 }
  # policy RemoteSigned + files marked as downloaded: must still run (the launcher unblocks its own files)
  'J2-remotesigned-policy' = @{ AdminPrep = "New-Item -Force 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell' | Out-Null; Set-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell' EnableScripts 1 -Type DWord; Set-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell' ExecutionPolicy RemoteSigned; Add-LocalGroupMember -Group Administrators -Member student; 'RemoteSigned policy set'"; Reboot = $true; Motw = $true; SetupArgs = '-Yes -DryRun'; MaxMin = 30 }
  # double-clicked inside the zip without extracting: only the .cmd is copied to a temp folder
  'K1-run-inside-zip' = @{ NoExtract = $true; CmdPath = '%TEMP%\Temp1_metascience-setup.zip\student-setup\install-windows.cmd';
                          UserPrep = '$d = "$env:TEMP\Temp1_metascience-setup.zip\student-setup"; New-Item -ItemType Directory -Force $d | Out-Null; Add-Type -A System.IO.Compression.FileSystem; $z = [IO.Compression.ZipFile]::OpenRead("C:\Users\Public\mstest\metascience-setup.zip"); $z.Entries | ? { $_.Name -eq "install-windows.cmd" } | % { [IO.Compression.ZipFileExtensions]::ExtractToFile($_, "$d\install-windows.cmd", $true) }; $z.Dispose(); Get-ChildItem $d | % Name'; MaxMin = 15 }
  # internet drops for 4 minutes in the middle of the install; then the student runs the setup again
  'C1-network-drop' = @{ AdminPrep = "Add-LocalGroupMember -Group Administrators -Member student"; Reboot = $true; Motw = $true; KeepRunning = $true;
                        During = '& $VB controlvm $VM setlinkstate1 off; Start-Sleep 240; & $VB controlvm $VM setlinkstate1 on; "network off for 4 min, back on"'; DuringAfterMin = 5 }
  'C2-rerun-after-drop' = @{ Snapshot = ''; Motw = $false; Extract = '%USERPROFILE%\Downloads\metascience-setup'; NoExtract = $true; CmdPath = '%USERPROFILE%\Downloads\metascience-setup\student-setup\install-windows.cmd' }
}
$Cases = @($Cases | ForEach-Object { $_ -split ',' } | Where-Object { $_ })   # -File passes "A,B" as one string
$list = if ($Cases.Count) { foreach ($want in $Cases) { $all.Keys | Where-Object { $_ -like "$want*" } } } else { $all.Keys }
foreach ($name in $list) {
  $p = $all[$name]
  Write-Output "########## $name  $(Get-Date -f HH:mm)"
  & (Join-Path $here 'run-case.ps1') -Tag $name @p 2>&1
}
Write-Output "########## night queue finished $(Get-Date -f HH:mm)"
