param (
    [Parameter(Mandatory=$true)]
    [string]
    $tenantId
)
function Get-OrphanedDisks {
    #Pull list of disks
    $disks = Get-AzDisk | Where-Object{$_.DiskState -eq "Unattached"}
    foreach($disk in $disks){
        #Dump resource info to object
        $diskObj = [pscustomobject]@{
            subscription = $sub.Id
            name =  $disk.Name
            rg = $disk.ResourceGroupName
            location = $disk.Location
            size = $disk.DiskSizeGB
            state = $disk.DiskState
        }
        $Script:diskArray += $diskObj
    }
}
function Get-OrphanedNics {
    #Pull list of nics
    $nics = Get-AzNetworkInterface
    foreach($nic in $nics){
        #Check if nic is connected to private link
        $ipconfigs = $nic.IpConfigurations
        $prvCount = 0
        foreach($config in $ipconfigs){
            $configName = $config.Name
            if($configName -like "*privateEndpoint*"){ $prvCount++}
        }
        #Determine if nic is part of a private link
        if($prvCount -gt 0){ 
            #Find prviate endpoint name
            $prvEdptName = $nic.Name.Split(".nic.")[0]
            #Pull info for private endpoint
            $prvEdpt = Get-AzPrivateEndpoint -Name $prvEdptName -ResourceGroupName $nic.ResourceGroupName
            #Pull connection status for the private endpoint
            $prvEdptStatus = $prvEdpt.PrivateLinkServiceConnections.PrivateLinkServiceConnectionState.Status
            $isEndpoint = "TRUE"
        }
        else{ 
            $isEndpoint = "FALSE" 
            $prvEdptStatus = "N/A"
        }
        #If nic is unattached to a VM, then it's orphaned
        if($nic.VirtualMachine.count -eq 0 -and $isEndpoint -eq "FALSE"){
            #Dump resource info to object
            $nicObj = [pscustomobject]@{
                subscription = $sub.Id
                name =  $nic.Name
                rg = $nic.ResourceGroupName
                location = $nic.Location
                privateEndpoint = $isEndpoint
                privateEndpointStatus = $prvEdptStatus
            }
            $Script:nicArray += $nicObj
        }
        #Add disconnected private endpoints to the array
        if($nic.VirtualMachine.count -eq 0 -and $isEndpoint -eq "TRUE" -and $prvEdptStatus -eq "Disconnected"){
            #Dump resource info to object
            $nicObj = [pscustomobject]@{
                subscription = $sub.Id
                name =  $nic.Name
                rg = $nic.ResourceGroupName
                location = $nic.Location
                privateEndpoint = $isEndpoint
                privateEndpointStatus = $prvEdptStatus
            }
            $Script:nicArray += $nicObj
        }
    }
}
function Get-OrphanedPublicIPs {
    #Pull list of pips
    $pips = Get-AzPublicIpAddress  | Where-Object{ $_.IpConfiguration.count -eq 0 }
    foreach($pip in $pips){
        #Dump resource info to object
        $pipObj = [pscustomobject]@{
            subscription = $sub.Id
            name =  $pip.Name
            rg = $pip.ResourceGroupName
            location = $pip.Location
        }
        $Script:pipArray += $pipObj
    }
}
function Get-OrphanedRGs {
    #Grab all resource groups
    $rgs = Get-AzResourceGroup
    foreach($rg in $rgs){
        #Grab number of resources in rg
        $resources = Get-AzResource -ResourceGroupName $rg.ResourceGroupName
        if($resources.count -eq 0){
            #Dump resource info to object
            $rgObj = [pscustomobject]@{
                subscription = $sub.Id
                rg = $rg.ResourceGroupName
                location = $rg.Location
            }
            $Script:rgArray += $rgObj
        }
    }
}
function Get-OrphanedVnets {
    #Grab all virtual networks in the subscription
    $vnets = Get-AzVirtualNetwork
    foreach($vnet in $vnets){
        #Get a lit of all subnets with the number of connected devices
        $vnetUsage = Get-AzVirtualNetworkUsageList -ResourceGroupName $vnet.ResourceGroupName -Name $vnet.Name
        $count = 0
        $gwCount = 0
        $bastionCount = 0
        $afwCount = 0
        #Check the count of all devices in all subnets in the vnet
        foreach($usage in $vnetUsage){
            $subnetName = $usage.Id.split("/")[-1]
            if($usage.CurrentValue -gt 0){ $count++ }
            if($subnetName -eq "GatewaySubnet"){ $gwCount++ }
            if($subnetName -eq "AzureBastionSubnet"){ $bastionCount++ }
            if($subnetName -eq "AzureFirewallSubnet"){ $afwCount++ }
            
        }
        #Check for managed subnets
        if($gwCount -gt 0){ $hasGatewaySubnet = "TRUE" }else{ $hasGatewaySubnet = "FALSE" }
        if($bastionCount -gt 0){ $hasBastionSubnet = "TRUE" }else{ $hasBastionSubnet = "FALSE" }
        if($afwCount -gt 0){ $hasFirewallSubnet = "TRUE" }else{ $hasFirewallSubnet = "FALSE" }
        #If all subnets are empty, dump info to object
        if($count -eq 0){
            $vnetObj = [pscustomobject]@{
                subscription = $sub.Id
                name = $vnet.Name
                rg = $vnet.ResourceGroupName
                location = $vnet.Location
                hasGateWaySubnet = $hasGatewaySubnet
                hasBastionSubnet = $hasBastionSubnet
                hasFirewallSubnet = $hasFirewallSubnet
            }
            $Script:vnetArray += $vnetObj
        }
    
    }
}
function Get-StoppedDealloctedVMs {
    #Pull list of VMs
    $vms = Get-AzVM
    foreach($vm in $vms){
        #Pull VM status
        $vmState = Get-AzVM -ResourceGroupName $vm.ResourceGroupName -Name $vm.Name -Status
        try{
            $vmCode = $vmState.Statuses[1].Code.Split("/")[1]
        }catch{ 
            Write-Verbose -Verbose "Cannot get VM state for $($vm.Name), skipping . . ."  
        }
        #Check if vm is stopped or deallocated
        if($vmCode -eq 'deallocated' -or $vmCode -eq 'stopped'){
            $vmObj = [pscustomobject]@{
                subscription = $sub.Id
                name = $vm.Name
                rg = $vm.ResourceGroupName
                location = $vm.Location
                status = $vmCode
            }
            $Script:vmArray += $vmObj
        }
    }
}
function Get-OrphanedNSGs {
    #Pull list of NSGs
    $nsgs = Get-AzNetworkSecurityGroup
    foreach($nsg in $nsgs){
        #Check if NSG is not attached to any subnets
        if($nsg.NetworkInterfaces.count -eq 0 -and $nsg.Subnets.count -eq 0){
            $nsgObj = [pscustomobject]@{
                subscription = $sub.Id
                name = $nsg.Name
                rg = $nsg.ResourceGroupName
                location = $nsg.Location
            }
            $Script:nsgArray += $nsgObj
        }
    }
}
function Get-OrphanedUDRs {
    
    #Pull list of UDRs
    $udrs = Get-AzRouteTable
    foreach($udr in $udrs){
        #Check if UDR is not attached to any subnets
        if($udr.Subnets.count -eq 0){
            $udrObj = [pscustomobject]@{
                subscription = $sub.Id
                name = $udr.Name
                rg = $udr.ResourceGroupName
                location = $udr.Location
            }
            $Script:udrArray += $udrObj
        }
    }
}
function Set-ArrayBlank {
    #No Disks
    if($Script:diskArray.count -eq 0){
        $noObj = [pscustomobject]@{
            result = 'No Orphaned Disks'
        }
        $Script:diskArray += $noObj
    }
    #No Nics
    if($Script:nicArray.count -eq 0){
        $noObj = [pscustomobject]@{
            result = 'No Orphaned NICs'
        }
        $Script:nicArray += $noObj
    }
    #No Public IPs
    if($Script:pipArray.count -eq 0){
        $noObj = [pscustomobject]@{
            result = 'No Orphaned Public IPs'
        }
        $Script:pipArray += $noObj
    }
    #No Resource Groups
    if($Script:rgArray.count -eq 0){
        $noObj = [pscustomobject]@{
            result = 'No Empty Resource Groups'
        }
        $Script:rgArray += $noObj
    }
    #No Vnets
    if($Script:vnetArray.count -eq 0){
        $noObj = [pscustomobject]@{
            result = 'No Empty Networks'
        }
        $Script:vnetArray += $noObj
    }
    #No Virtual Machines
    if($Script:vmArray.count -eq 0){
        $noObj = [pscustomobject]@{
            result = 'No Stopped/Deallocatd VMs'
        }
        $Script:vmArray += $noObj
    }
    #No NSGs
    if($Script:nsgArray.count -eq 0){
        $noObj = [pscustomobject]@{
            result = 'No Unattached NSGs'
        }
        $Script:nsgArray += $noObj
    }
    #No UDRs
    if($Script:udrArray.count -eq 0){
        $noObj = [pscustomobject]@{
            result = 'No Unattached UDRs'
        }
        $Script:udrArray += $noObj
    }
}
#Quiet warnings
$WarningPreference = "SilentlyContinue"
#Check for existence of ImportExcel Module
$modCheck = Get-InstalledModule -Name 'ImportExcel' -ErrorAction SilentlyContinue
if(!$modCheck){
    Write-Verbose -Verbose 'ImoprtExcel module not found, please run Install-Module -Name ImportExcel and try again'
    exit
}else{
    Write-Host -ForegroundColor Cyan 'Importing ImportExcel . . .'
    Import-Module 'ImportExcel'
}
#Set the Excel outputs
Write-Host -ForegroundColor Cyan 'Setting Excel file name . . .'
$today=Get-Date -Format "MM-dd-yyyy"
$excelFile = ".\Orphaned-Resources-" + $today + ".xlsx"
#Set arrays and worksheet names
$diskWsName = "Disks (Unattached)"
$diskArray = @()
$nicWsName = "NICs (Unattached)"
$nicArray = @()
$vnetWsName = "VNETs (No Connected Devices)"
$vnetArray = @()
$pipWsName = "Public IPs (Unattached)"
$pipArray = @()
$rgWsName = "Resource Groups (Empty)"
$rgArray = @()
$vmWsName = "VMs (Deallocated)"
$vmArray = @()
$nsgWsName = "NSG (Unattached)"
$nsgArray = @()
$udrWsName = "UDR (Unattached)"
$udrArray = @()
#Login to Azure
try{
    Write-Host -ForegroundColor Cyan "Signing in to Azure Portal . . ."
    Connect-AzAccount | Out-Null
}catch{
    Write-Verbose -Verbose "Failure connecting to the Azure Portal."
    exit
}
#Grab customer's subscriptions
try{
    Write-Host -ForegroundColor Cyan "Grabbing customer's subscriptions using tenantId: $tenantId . . ."
    $subscriptions = Get-AzSubscription | Where-Object{$_.HomeTenantId -eq $tenantId}
}catch{
    Write-Verbose -Verbose "Could not pull subscriptions for $tenantId . . ."
    exit
}
#Get all subs and iterate through
foreach ($sub in $subscriptions){
    
    #Select proper subscription
    try{
        Set-AzContext -SubscriptionId $sub.Id | Out-Null
    }
    catch{
        Write-Error "Couldnt select $($sub.Id)" -ErrorAction Stop
    }
    Write-Host -ForegroundColor Cyan "Collecting unused resources for $($sub.Id) . . ."
    Get-OrphanedDisks
    Get-OrphanedVnets
    Get-OrphanedNics
    Get-OrphanedNSGs
    Get-OrphanedUDRs
    Get-OrphanedPublicIPs
    Get-OrphanedRGs
    Get-StoppedDealloctedVMs
}
#Verify if any arrays are empty before exporting
Set-ArrayBlank
Write-Host -ForegroundColor Cyan 'Exporting unused resource info to Excel . . .'
$vmArray | Export-Excel -Path $excelFile -AutoSize -TableName VMs -WorksheetName $vmWsName
$vnetArray | Export-Excel -Path $excelFile -AutoSize -TableName Vnets -WorksheetName $vnetWsName
$diskArray | Export-Excel -Path $excelFile -AutoSize -TableName Disks -WorksheetName $diskWsName
$nicArray | Export-Excel -Path $excelFile -AutoSize -TableName Nics -WorksheetName $nicWsName
$nsgArray | Export-Excel -Path $excelFile -AutoSize -TableName NSGs -WorksheetName $nsgWsName
$udrArray | Export-Excel -Path $excelFile -AutoSize -TableName UDRs -WorksheetName $udrWsName
$pipArray | Export-Excel -Path $excelFile -AutoSize -TableName Pips -WorksheetName $pipWsName
$rgArray | Export-Excel -Path $excelFile -AutoSize -TableName Rgs -WorksheetName $rgWsName
Write-Host -ForegroundColor Cyan 'Finished exporting unused resource info to Excel . . .'


