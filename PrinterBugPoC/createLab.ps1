$labName = 'Printer'
$IP = "192.168.14"

#create an empty lab template and define where the lab XML files and the VMs will be stored
New-LabDefinition -Name $labName -DefaultVirtualizationEngine HyperV -VmPath D:\AutomatedLab-VMs
Add-LabVirtualNetworkDefinition -Name $labName -AddressSpace $IP'.0/24'

#and the domain definition with the domain admin account
Add-LabDomainDefinition -Name forest1.net -AdminUser Install -AdminPassword Somepass1
Add-LabDomainDefinition -Name forest2.net -AdminUser Install -AdminPassword Somepass2

#--------------------------------------------------------------------------------------------------------------------
# Domain 1
Set-LabInstallationCredential -Username Install -Password Somepass1

$postInstallActivity = Get-LabPostInstallationActivity -ScriptFileName PrepareRootDomain.ps1 -DependencyFolder $labSources\PostInstallationActivities\PrepareRootDomain

Add-LabMachineDefinition -Name "DC1" -DomainName forest1.net -Roles RootDC -PostInstallationActivity $postInstallActivity `
  -OperatingSystem 'Windows Server 2012 R2 Datacenter Evaluation (Server with a GUI)' -Memory 2GB -ToolsPath ".\Tools"

#--------------------------------------------------------------------------------------------------------------------
# Domain 2
Set-LabInstallationCredential -Username Install -Password Somepass2

$postInstallActivity = Get-LabPostInstallationActivity -ScriptFileName PrepareRootDomain.ps1 -DependencyFolder $labSources\PostInstallationActivities\PrepareRootDomain

Add-LabMachineDefinition -Name "DC2" -DomainName forest2.net -Roles RootDC -PostInstallationActivity $postInstallActivity `
  -OperatingSystem 'Windows Server 2012 R2 Datacenter Evaluation (Server with a GUI)' -Memory 2GB

#--------------------------------------------------------------------------------------------------------------------
# Adding router to get Internet (no need if the lab switch is already on Internet)
Set-LabInstallationCredential -Username Install -Password RouterPass
Add-LabVirtualNetworkDefinition -Name External -HyperVProperties @{ SwitchType = 'External'; AdapterName = 'Ethernet' }
$netAdapter = @()
$netAdapter += New-LabNetworkAdapterDefinition -VirtualSwitch $labName -Ipv4Address "$($IP).250"
$netAdapter += New-LabNetworkAdapterDefinition -VirtualSwitch External -UseDhcp

$roles = Get-LabMachineRoleDefinition -Role Routing
Add-LabMachineDefinition -Name "Router" -NetworkAdapter $netAdapter -Roles $roles -OperatingSystem 'Windows Server 2012 R2 Datacenter Evaluation (Server with a GUI)' -Memory 2GB

#--------------------------------------------------------------------------------------------------------------------
Install-Lab

Show-LabDeploymentSummary -Detailed

#--------------------------------------------------------------------------------------------------------------------
# Activating virtual machines
Set-LabInstallationCredential -Username Install -Password Somepass1
Invoke-LabCommand -ScriptBlock { slmgr -rearm } -ComputerName "DC1" -PassThru

Set-LabInstallationCredential -Username Install -Password Somepass2
Invoke-LabCommand -ScriptBlock { slmgr -rearm } -ComputerName "DC2" -PassThru

#--------------------------------------------------------------------------------------------------------------------
# Installing .NET
Set-LabInstallationCredential -Username Install -Password Somepass1
Invoke-LabCommand -ScriptBlock { Install-WindowsFeature Net-Framework-Core } -ComputerName "DC1" -PassThru

Set-LabInstallationCredential -Username Install -Password Somepass2
Invoke-LabCommand -ScriptBlock { Install-WindowsFeature Net-Framework-Core } -ComputerName "DC2" -PassThru

#--------------------------------------------------------------------------------------------------------------------
Set-LabInstallationCredential -Username Install -Password Somepass1

# Creating bidirectional trust from forest1 to forest2 
Invoke-LabCommand -ComputerName "DC1" -ScriptBlock {netdom trust forest1.net /d:forest2.net /add /twoway /UserD:Install@forest2.net /PasswordD:Somepass2 /UserO:Install@forest1.net /PasswordO:Somepass1}

Checkpoint-LabVM -All -SnapshotName 'ReadyToExploit'