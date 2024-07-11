﻿##.\ElevateMultipleSubPIM.ps1 -hometenantid "52336fb4-b643-498d-8fb3-9fb84e6c186d" -role "Contributor" -user "v-nshaikh@3Cloudsolutions.com" -hours "8" -reason "https://3cloud.zendesk.com/agent/tickets/199432"
###
##.\ElevateMultipleSubPIM.ps1 -hometenantid "52336fb4-b643-498d-8fb3-9fb84e6c186d" -role "Resource Policy Contributor" -user "v-nshaikh@3Cloudsolutions.com" -hours "8" -reason "https://3cloud.zendesk.com/agent/tickets/199432"

param(
    [Parameter (Mandatory= $true)]
    [String] $hometenantid,
    [Parameter (Mandatory= $true)]
    [String] $user,
    [Parameter (Mandatory= $true)]
    [String] $hours,
    [Parameter (Mandatory= $true)]
    [String] $reason,
    [Parameter(Mandatory)]
    [ValidateSet("Contributor","Resource Policy Contributor")]
    [String] $role
    )
if($PSVersionTable.PSVersion.Major -eq "7")
{
    Write-Host "You're current running Powershell Core. Please re-run this using Powershell 5.1"
}

else 
{
$VarAzureAdPreview = Get-InstalledModule -Name AzureADPreview -ErrorAction silentlycontinue
if ($null -eq $VarAzureAdPreview) 
    {
        Write-Host "Trying to install AzureADPreview Module..."
        Install-Module -Name AzureADPreview -Force
    }
else
    {
        Write-Host "AzureADPreview module is installed."
    }
import-module AzureADPreview
Write-Host "Connect to Azure AD using your 3Cloud admin credentials"
connect-azuread
connect-azaccount
$subscriptions = get-azsubscription | where-object{$_.hometenantid -eq "$($hometenantid)"}
foreach($subscription in $subscriptions)
{
    try
    {
        if($role -eq "Contributor")
        {
            $roleDefinitionID = "b24988ac-6180-42a0-ab88-20f7382dd24c" #Built-in Contributor Role Definition ID
        }
        elseif($role -eq "Resource Policy Contributor")
        {
            $roleDefinitionID = "36243c78-bf99-498c-9df9-86d9f8d28608" #Built-in Resource Policy Contributor Role Definition ID
        }
        $subscriptionID = $subscription.Id
        Write-Host "Subscription ID is $($subscriptionID)"

        $targetuserID = (Get-AzureADUser -ObjectId $user).ObjectId  # Replace user ID
        $SubscriptionPIMID = (Get-AzureADMSPrivilegedResource -ProviderId 'AzureResources' -Filter "ExternalId eq '/subscriptions/$subscriptionID'").Id
        $RoleDefinitionPIMID = (Get-AzureADMSPrivilegedRoleDefinition -ProviderId 'AzureResources' -Filter "ExternalId eq '/subscriptions/$subscriptionID/providers/Microsoft.Authorization/roleDefinitions/$roleDefinitionID'" -ResourceId $subscriptionPIMID).Id
        
        $schedule = New-Object Microsoft.Open.MSGraph.Model.AzureADMSPrivilegedSchedule
        $schedule.Type = "Once"
        $schedule.StartDateTime = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
        $schedule.EndDateTime =  ((Get-Date).AddHours($hours)).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
        start-sleep 2

        Write-Host "Activating $($role) role for $($subscription.Name)"
        Open-AzureADMSPrivilegedRoleAssignmentRequest -ProviderId 'AzureResources' -ResourceId $SubscriptionPIMID -RoleDefinitionId $RoleDefinitionPIMID -SubjectId $targetuserID -Type 'UserAdd' -AssignmentState 'Active' -schedule $schedule -reason "$($Reason)"


    }
    catch 
    {
        Write-Host "Unable to activate PIM role for $($subscription.Name)"
    }
}
    
}
