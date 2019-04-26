$labName = 'SID'
$IP = "192.168.15"

#create an empty lab template and define where the lab XML files and the VMs will be stored
New-LabDefinition -Name $labName -DefaultVirtualizationEngine HyperV -VmPath D:\AutomatedLab-VMs
Add-LabVirtualNetworkDefinition -Name $labName -AddressSpace $IP'.0/24'

#and the domain definition with the domain admin account
Add-LabDomainDefinition -Name forest1.net -AdminUser user_ea -AdminPassword Somepass1
Add-LabDomainDefinition -Name forest2.net -AdminUser user_ea -AdminPassword Somepass2
Add-LabDomainDefinition -Name sub.forest1.net -AdminUser user_da -AdminPassword Somepass1sub

#--------------------------------------------------------------------------------------------------------------------
# Domain 1
Set-LabInstallationCredential -Username user_ea -Password Somepass1

$postInstallActivity = Get-LabPostInstallationActivity -ScriptFileName PrepareRootDomain.ps1 -DependencyFolder $labSources\PostInstallationActivities\PrepareRootDomain

Add-LabMachineDefinition -Name "$($labName)-DC1" -DomainName forest1.net -Roles RootDC -PostInstallationActivity $postInstallActivity `
  -OperatingSystem 'Windows Server 2012 R2 Datacenter Evaluation (Server with a GUI)' -Memory 2GB -ToolsPath ".\Tools"
  
#--------------------------------------------------------------------------------------------------------------------
# Domain 1SUB
Set-LabInstallationCredential -Username user_da -Password Somepass1sub

$roles = Get-LabMachineRoleDefinition -Role FirstChildDC -Properties @{ ParentDomain = 'forest1.net'; NewDomain = 'sub'; DomainFunctionalLevel = 'Win2012R2' }
Add-LabMachineDefinition -Name "$($labName)-DC1SUB" -DomainName sub.forest1.net -Roles $roles `
  -OperatingSystem 'Windows Server 2012 R2 Datacenter Evaluation (Server with a GUI)' -Memory 2GB -ToolsPath ".\Tools" -PostInstallationActivity $postInstallActivity
  
#--------------------------------------------------------------------------------------------------------------------

# Domain 2
Set-LabInstallationCredential -Username user_ea -Password Somepass2

$postInstallActivity = Get-LabPostInstallationActivity -ScriptFileName PrepareRootDomain.ps1 -DependencyFolder $labSources\PostInstallationActivities\PrepareRootDomain

Add-LabMachineDefinition -Name "$($labName)-DC2" -DomainName forest2.net -Roles RootDC -PostInstallationActivity $postInstallActivity `
  -OperatingSystem 'Windows Server 2012 R2 Datacenter Evaluation (Server with a GUI)' -Memory 2GB

$postInstallActivity = Get-LabPostInstallationActivity -CustomRole Exchange2013 -Properties @{ OrganizationName = 'ExOrg' }
Add-LabMachineDefinition -Name "$($labName)-EXCHANGE" -DomainName forest2.net `
  -OperatingSystem 'Windows Server 2012 R2 Datacenter Evaluation (Server with a GUI)' -Memory 2GB -PostInstallationActivity $postInstallActivity

  
#--------------------------------------------------------------------------------------------------------------------
# Adding router to get Internet (no need if the lab switch is already on Internet)
Set-LabInstallationCredential -Username Install -Password RouterPass
Add-LabVirtualNetworkDefinition -Name External -HyperVProperties @{ SwitchType = 'External'; AdapterName = 'Ethernet' }
$netAdapter = @()
$netAdapter += New-LabNetworkAdapterDefinition -VirtualSwitch $labName -Ipv4Address "$($IP).250"
$netAdapter += New-LabNetworkAdapterDefinition -VirtualSwitch External -UseDhcp

$roles = Get-LabMachineRoleDefinition -Role Routing
Add-LabMachineDefinition -Name "$($labName)-Router" -NetworkAdapter $netAdapter -Roles $roles -OperatingSystem 'Windows Server 2012 R2 Datacenter Evaluation (Server with a GUI)' -Memory 2GB

#--------------------------------------------------------------------------------------------------------------------
Install-Lab

Show-LabDeploymentSummary -Detailed

#--------------------------------------------------------------------------------------------------------------------
# Activating virtual machines
Set-LabInstallationCredential -Username user_ea -Password Somepass1
Invoke-LabCommand -ScriptBlock { slmgr -rearm } -ComputerName "$($labName)-DC1" -PassThru

Set-LabInstallationCredential -Username user_da -Password Somepass1sub
Invoke-LabCommand -ScriptBlock { slmgr -rearm } -ComputerName "$($labName)-DC1SUB" -PassThru

Set-LabInstallationCredential -Username user_ea -Password Somepass2
Invoke-LabCommand -ScriptBlock { slmgr -rearm } -ComputerName "$($labName)-DC2" -PassThru

#--------------------------------------------------------------------------------------------------------------------
# Adding an enterprise admin user for forest1 domain
Set-LabInstallationCredential -Username user_ea -Password Somepass1
Invoke-LabCommand -ComputerName "$($labName)-DC1" -ScriptBlock {Add-ADGroupMember -Identity "Enterprise Admins" -Members "user_ea"}
    
# Adding an enterprise admin user for forest2 domain
Set-LabInstallationCredential -Username user_ea -Password Somepass2
Invoke-LabCommand -ComputerName "$($labName)-DC2" -ScriptBlock {Add-ADGroupMember -Identity "Enterprise Admins" -Members "user_ea"}
  
#--------------------------------------------------------------------------------------------------------------------
# Creating bidirectional trust from forest1 to forest2 
Set-LabInstallationCredential -Username user_ea -Password Somepass1
Invoke-LabCommand -ComputerName "$($labName)-DC1" -ScriptBlock {netdom trust forest1.net /d:forest2.net /enablesidhistory:Yes}

# Creating bidirectional trust from forest2 to forest1 
Set-LabInstallationCredential -Username user_ea -Password Somepass2
Invoke-LabCommand -ComputerName "$($labName)-DC2" -ScriptBlock {netdom trust forest2.net /d:forest1.net /enablesidhistory:Yes}

Checkpoint-LabVM -All -SnapshotName 'ReadyToExploit'