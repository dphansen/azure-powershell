# ----------------------------------------------------------------------------------
#
# Copyright Microsoft Corporation
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# http://www.apache.org/licenses/LICENSE-2.0
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
# ----------------------------------------------------------------------------------

########################## Site Recovery Tests #############################

$JobQueryWaitTimeInSeconds = 30
$ResourceGroupName = "siterecoveryprod1"
$VaultName = "b2aRSvaultprod17012017"
$FabricNameToBeCreated = "ReleaseFabric"
$PrimaryFabricName = "CP-B3L30107-23.ntdev.corp.microsoft.com"
$RecoveryFabricName = "CP-B3L40104-01.ntdev.corp.microsoft.com"
$PolicyName = "E2EPolicy1"
$PrimaryProtectionContainerName = "E2ECloudProdJun08"
$RecoveryProtectionContainerName = "E2ERProdJun08"
$ProtectionContainerMappingName = "E2AClP26mapping"
$PrimaryNetworkFriendlyName = "corp"
$RecoveryNetworkFriendlyName = "corp"
$NetworkMappingName = "corp96map"
$VMName = "E2EVMP96"
$RecoveryPlanName = "RPSwag96"

<#
.SYNOPSIS
Wait for job completion
Usage:
	WaitForJobCompletion -JobId $Job.ID
	WaitForJobCompletion -JobId $Job.ID -NumOfSecondsToWait 10
#>
function WaitForJobCompletion
{ 
	param(
        [string] $JobId,
        [int] $JobQueryWaitTimeInSeconds = 60
        )
        $isJobLeftForProcessing = $true;
        do
        {
            $Job = Get-AzureRmRecoveryServicesAsrJob -Name $JobId
            $Job

            if($Job.State -eq "InProgress" -or $Job.State -eq "NotStarted")
            {
	            $isJobLeftForProcessing = $true
            }
            else
            {
                $isJobLeftForProcessing = $false
            }

            if($isJobLeftForProcessing)
	        {
		        Start-Sleep -Seconds $JobQueryWaitTimeInSeconds
	        }
        }While($isJobLeftForProcessing)
}

<#
.SYNOPSIS
Wait for IR job completion
Usage:
	WaitForJobCompletion -VM $VM
	WaitForJobCompletion -VM $VM -NumOfSecondsToWait 10
#>
Function WaitForIRCompletion
{ 
	param(
        [PSObject] $VM,
        [int] $JobQueryWaitTimeInSeconds = 60
        )
        $isProcessingLeft = $true
        $IRjobs = $null

        do
        {
            $IRjobs = Get-AzureRmRecoveryServicesAsrJob -TargetObjectId $VM.Name | Sort-Object StartTime -Descending | select -First 4 | Where-Object{$_.JobType -eq "PrimaryIrCompletion" -or $_.JobType -eq "SecondaryIrCompletion"}
            if($IRjobs -eq $null -or $IRjobs.Count -lt 2)
            {
	            $isProcessingLeft = $true
            }
            else
            {
                $isProcessingLeft = $false
            }

            if($isProcessingLeft)
	        {
		        Start-Sleep -Seconds $JobQueryWaitTimeInSeconds
	        }
        }While($isProcessingLeft)

        $IRjobs
        WaitForJobCompletion -JobId $IRjobs[0].Name -JobQueryWaitTimeInSeconds $JobQueryWaitTimeInSeconds
        WaitForJobCompletion -JobId $IRjobs[1].Name -JobQueryWaitTimeInSeconds $JobQueryWaitTimeInSeconds
}

<#
.SYNOPSIS
Site Recovery Enumeration Tests
#>
function Test-SiteRecoveryEnumerationTests
{
	param([string] $vaultSettingsFilePath)

	# Import Azure RecoveryServices Vault Settings File
	Import-AzureRmRecoveryServicesAsrVaultSettingsFile -Path $vaultSettingsFilePath

	# Enumerate Vaults
	$vaults = Get-AzureRmRecoveryServicesVault
	Assert-True { $vaults.Count -gt 0 }
	Assert-NotNull($vaults)
	foreach($vault in $vaults)
	{
		Assert-NotNull($vault.Name)
		Assert-NotNull($vault.ID)
	}

	# Enumerate Recovery Services Providers
	$rsps = Get-AzureRmRecoveryServicesAsrFabric | Get-AzureRmRecoveryServicesAsrServicesProvider
	Assert-True { $rsps.Count -gt 0 }
	Assert-NotNull($rsps)
	foreach($rsp in $rsps)
	{
		Assert-NotNull($rsp.Name)
		Assert-NotNull($rsp.ID)
	}

	# Enumerate Protection Containers
	$protectionContainers = Get-AzureRmRecoveryServicesAsrFabric | Get-AzureRmRecoveryServicesAsrProtectionContainer
	Assert-True { $protectionContainers.Count -gt 0 }
	Assert-NotNull($protectionContainers)
	foreach($protectionContainer in $protectionContainers)
	{
		Assert-NotNull($protectionContainer.Name)
		Assert-NotNull($protectionContainer.ID)
	}
}

<#
.SYNOPSIS
Site Recovery Create Policy Test
#>
function Test-SiteRecoveryCreatePolicy
{
	param([string] $vaultSettingsFilePath)

	# Import Azure RecoveryServices Vault Settings File
	Import-AzureRmRecoveryServicesAsrVaultSettingsFile -Path $vaultSettingsFilePath

	# Create profile
	$Job = New-AzureRmRecoveryServicesAsrPolicy -Name $PolicyName -ReplicationProvider HyperVReplica2012R2 -ReplicationMethod Online -ReplicationFrequencyInSeconds 30 -RecoveryPoints 1 -ApplicationConsistentSnapshotFrequencyInHours 0 -ReplicationPort 8083 -Authentication Kerberos -ReplicaDeletion Required 
	#WaitForJobCompletion -JobId $Job.Name -JobQueryWaitTimeInSeconds $JobQueryWaitTimeInSeconds

	# Get a profile created (with name ppAzure)
	$Policy = Get-AzureRmRecoveryServicesAsrPolicy -Name $PolicyName
	Assert-True { $Policy.Count -gt 0 }
	Assert-NotNull($Policy)
}

<#
.SYNOPSIS
Site Recovery remove Policy Test
#>
function Test-SiteRecoveryRemovePolicy
{
	param([string] $vaultSettingsFilePath)

	# Import Azure RecoveryServices Vault Settings File
	Import-AzureRmRecoveryServicesAsrVaultSettingsFile -Path $vaultSettingsFilePath

	# Get a policy created in previous test
	$Policy = Get-AzureRmRecoveryServicesAsrPolicy -Name $PolicyName
	Assert-True { $Policy.Count -gt 0 }
	Assert-NotNull($Policy)

	# Delete the profile
	$Job = Remove-AzureRmRecoveryServicesAsrPolicy -Policy $Policy
	#WaitForJobCompletion -JobId $Job.Name
}

<#
.SYNOPSIS
Site Recovery new protection container mapping test
#>
function Test-CreatePCMap
{
	param([string] $vaultSettingsFilePath)

	# Import Azure RecoveryServices Vault Settings File
	Import-AzureRmRecoveryServicesAsrVaultSettingsFile -Path $vaultSettingsFilePath

	# Get the containers and policy
	$Policy = Get-AzureRmRecoveryServicesAsrPolicy -Name $PolicyName;
	$PrimaryProtectionContainer = Get-AzureRmRecoveryServicesAsrFabric | Get-AzureRmRecoveryServicesAsrProtectionContainer | where { $_.FriendlyName -eq $PrimaryProtectionContainerName }
	$RecoveryProtectionContainer = Get-AzureRmRecoveryServicesAsrFabric | Get-AzureRmRecoveryServicesAsrProtectionContainer | where { $_.FriendlyName -eq $RecoveryProtectionContainerName }

	# Associate the profile
	$Job = New-AzureRmRecoveryServicesAsrProtectionContainerMapping -Name $ProtectionContainerMappingName -Policy $Policy -PrimaryProtectionContainer $PrimaryProtectionContainer -RecoveryProtectionContainer $RecoveryProtectionContainer
	#WaitForJobCompletion -JobId $Job.Name

	# Get protection conatiner mapping
	$ProtectionContainerMapping = Get-AzureRmRecoveryServicesAsrProtectionContainerMapping -Name $ProtectionContainerMappingName -ProtectionContainer $PrimaryProtectionContainer
	Assert-NotNull($ProtectionContainerMapping)
}


<#
.SYNOPSIS
Site Recovery remove protection container mapping test
#>
function Test-RemovePCMap
{
	param([string] $vaultSettingsFilePath)

	# Import Azure RecoveryServices Vault Settings File
	Import-AzureRmRecoveryServicesAsrVaultSettingsFile -Path $vaultSettingsFilePath

	# Get the primary container
	$PrimaryProtectionContainer = Get-AzureRmRecoveryServicesAsrFabric | Get-AzureRmRecoveryServicesAsrProtectionContainer | where { $_.FriendlyName -eq $PrimaryProtectionContainerName }

	# Get protection conatiner mapping
	$ProtectionContainerMapping = Get-AzureRmRecoveryServicesAsrProtectionContainerMapping -Name $ProtectionContainerMappingName -ProtectionContainer $PrimaryProtectionContainer

	# Remove protection conatiner mapping
	$Job = Remove-AzureRmRecoveryServicesAsrProtectionContainerMapping -ProtectionContainerMapping $ProtectionContainerMapping
	#WaitForJobCompletion -JobId $Job.Name
}

<#
.SYNOPSIS
Site Recovery Enable protection Test
#>
function Test-SiteRecoveryEnableDR
{
	param([string] $vaultSettingsFilePath)

	# Import Azure RecoveryServices Vault Settings File
	Import-AzureRmRecoveryServicesAsrVaultSettingsFile -Path $vaultSettingsFilePath

	# Get the primary container
	$PrimaryProtectionContainer = Get-AzureRmRecoveryServicesAsrFabric | Get-AzureRmRecoveryServicesAsrProtectionContainer | where { $_.FriendlyName -eq $PrimaryProtectionContainerName }

	# Get protection container mapping
	$ProtectionContainerMapping = Get-AzureRmRecoveryServicesAsrProtectionContainerMapping -Name $ProtectionContainerMappingName -ProtectionContainer $PrimaryProtectionContainer

	# Get protectable item
	$VM = Get-AzureRmRecoveryServicesAsrProtectableItem -FriendlyName $VMName -ProtectionContainer $PrimaryProtectionContainer  

	# EnableDR
	$Job = New-AzureRmRecoveryServicesAsrReplicationProtectedItem -ProtectableItem $VM -Name $VM.Name -ProtectionContainerMapping $ProtectionContainerMapping
	#WaitForJobCompletion -JobId $Job.Name
	#WaitForIRCompletion -VM $VM 
}

<#
.SYNOPSIS
Site Recovery Disable protection Test
#>
function Test-SiteRecoveryDisableDR
{
	param([string] $vaultSettingsFilePath)

	# Import Azure RecoveryServices Vault Settings File
	Import-AzureRmRecoveryServicesAsrVaultSettingsFile -Path $vaultSettingsFilePath

	# Get the primary container
	$PrimaryProtectionContainer = Get-AzureRmRecoveryServicesAsrFabric | Get-AzureRmRecoveryServicesAsrProtectionContainer | where { $_.FriendlyName -eq $PrimaryProtectionContainerName }

	# Get protected item
	$VM = Get-AzureRmRecoveryServicesAsrReplicationProtectedItem -FriendlyName $VMName -ProtectionContainer $PrimaryProtectionContainer  

	# DisableDR
	$Job = Remove-AzureRmRecoveryServicesAsrReplicationProtectedItem -ReplicationProtectedItem $VM
	#WaitForJobCompletion -JobId $Job.Name
}

<#
.SYNOPSIS
Site Recovery Create Recovery Plan Test
#>
function Test-SiteRecoveryCreateRecoveryPlan
{
	param([string] $vaultSettingsFilePath)

	# Import Azure RecoveryServices Vault Settings File
	Import-AzureRmRecoveryServicesAsrVaultSettingsFile -Path $vaultSettingsFilePath

	# Get the fabric and container
	$PrimaryFabric = Get-AzureRmRecoveryServicesAsrFabric -FriendlyName $PrimaryFabricName
	$RecoveryFabric = Get-AzureRmRecoveryServicesAsrFabric -FriendlyName $RecoveryFabricName
	$PrimaryProtectionContainer = Get-AzureRmRecoveryServicesAsrProtectionContainer -FriendlyName $PrimaryProtectionContainerName -Fabric $PrimaryFabric
	$VM = Get-AzureRmRecoveryServicesAsrReplicationProtectedItem -FriendlyName $VMName -ProtectionContainer $PrimaryProtectionContainer

	$Job = New-AzureRmRecoveryServicesAsrRecoveryPlan -Name $RecoveryPlanName -PrimaryFabric $PrimaryFabric -RecoveryFabric $RecoveryFabric -ReplicationProtectedItem $VM
	#WaitForJobCompletion -JobId $Job.Name
}

<#
.SYNOPSIS
Site Recovery Enumerate Recovery Plan Test
#>
function Test-SiteRecoveryEnumerateRecoveryPlan
{
	param([string] $vaultSettingsFilePath)

	# Import Azure RecoveryServices Vault Settings File
	Import-AzureRmRecoveryServicesAsrVaultSettingsFile -Path $vaultSettingsFilePath

	$RP = Get-AzureRmRecoveryServicesAsrRecoveryPlan -Name $RecoveryPlanName
	Assert-NotNull($RP)
	Assert-True { $RP.Count -gt 0 }
}

<#
.SYNOPSIS
Site Recovery Remove Recovery Plan Test
#>
function Test-SiteRecoveryRemoveRecoveryPlan
{
	param([string] $vaultSettingsFilePath)

	# Import Azure RecoveryServices Vault Settings File
	Import-AzureRmRecoveryServicesAsrVaultSettingsFile -Path $vaultSettingsFilePath

	$RP = Get-AzureRmRecoveryServicesAsrRecoveryPlan -Name $RecoveryPlanName
	$Job = Remove-AzureRmRecoveryServicesAsrRecoveryPlan -RecoveryPlan $RP
	#WaitForJobCompletion -JobId $Job.Name
}

<#
.SYNOPSIS
Site Recovery Fabric Tests New model
#>
function Test-SiteRecoveryFabricTest
{
	param([string] $vaultSettingsFilePath)

	# Import Azure RecoveryServices Vault Settings File
	Import-AzureRmRecoveryServicesAsrVaultSettingsFile -Path $vaultSettingsFilePath

	# Create Fabric
	$Job = New-AzureRmRecoveryServicesAsrFabric -Name $FabricNameToBeCreated -Type HyperVSite
	#WaitForJobCompletion -JobId $Job.Name -JobQueryWaitTimeInSeconds $JobQueryWaitTimeInSeconds
	Assert-NotNull($Job)

	# Enumerate Fabrics
	$fabrics =  Get-AzureRmRecoveryServicesAsrFabric 
	Assert-True { $fabrics.Count -gt 0 }
	Assert-NotNull($fabrics)
	foreach($fabric in $fabrics)
	{
		Assert-NotNull($fabrics.Name)
		Assert-NotNull($fabrics.ID)
	}

	# Enumerate specific Fabric
	$fabric =  Get-AzureRmRecoveryServicesAsrFabric -Name $FabricNameToBeCreated
	Assert-NotNull($fabric)
	Assert-NotNull($fabrics.Name)
	Assert-NotNull($fabrics.ID)

	# Remove specific fabric
	$Job = Remove-AzureRmRecoveryServicesAsrFabric -Fabric $fabric
	Assert-NotNull($Job)
	#WaitForJobCompletion -JobId $Job.Name -JobQueryWaitTimeInSeconds $JobQueryWaitTimeInSeconds
	$fabric =  Get-AzureRmRecoveryServicesAsrFabric | Where-Object {$_.Name -eq $FabricNameToBeCreated }
	Assert-Null($fabric)
}


<#
.SYNOPSIS
Site Recovery New model End to End
#>
function Test-SiteRecoveryNewModelE2ETest
{
	param([string] $vaultSettingsFilePath)

	# Import Azure RecoveryServices Vault Settings File
	Import-AzureRmRecoveryServicesAsrVaultSettingsFile -Path $vaultSettingsFilePath

	# Enumerate Fabrics
	$Fabrics =  Get-AzureRmRecoveryServicesAsrFabric 
	Assert-True { $fabrics.Count -gt 0 }
	Assert-NotNull($fabrics)
	foreach($fabric in $fabrics)
	{
		Assert-NotNull($fabrics.Name)
		Assert-NotNull($fabrics.ID)
	}
	$PrimaryFabric = $Fabrics | Where-Object { $_.FriendlyName -eq $PrimaryFabricName}
	$RecoveryFabric = $Fabrics | Where-Object { $_.FriendlyName -eq $RecoveryFabricName}

	# Enumerate RSPs
	$rsps = Get-AzureRmRecoveryServicesAsrFabric | Get-AzureRmRecoveryServicesAsrServicesProvider
	Assert-True { $rsps.Count -gt 0 }
	Assert-NotNull($rsps)
	foreach($rsp in $rsps)
	{
		Assert-NotNull($rsp.Name)
	}

	# Create Policy
	$Job = New-AzureRmRecoveryServicesAsrPolicy -Name $PolicyName -ReplicationProvider HyperVReplica2012R2 -ReplicationMethod Online -ReplicationFrequencyInSeconds 30 -RecoveryPoints 1 -ApplicationConsistentSnapshotFrequencyInHours 0 -ReplicationPort 8083 -Authentication Kerberos -ReplicaDeletion Required
	#WaitForJobCompletion -JobId $Job.Name

    $Policy = Get-AzureRmRecoveryServicesAsrPolicy -Name $PolicyName
	Assert-NotNull($Policy)
	Assert-NotNull($Policy.Name)

	# Get conatiners
	$PrimaryProtectionContainer = Get-AzureRmRecoveryServicesAsrFabric | Get-AzureRmRecoveryServicesAsrProtectionContainer | where { $_.FriendlyName -eq $PrimaryProtectionContainerName }
	Assert-NotNull($PrimaryProtectionContainer)
	Assert-NotNull($PrimaryProtectionContainer.Name)
	$RecoveryProtectionContainer = Get-AzureRmRecoveryServicesAsrFabric | Get-AzureRmRecoveryServicesAsrProtectionContainer | where { $_.FriendlyName -eq $RecoveryProtectionContainerName }
	Assert-NotNull($RecoveryProtectionContainer)
	Assert-NotNull($RecoveryProtectionContainer.Name)

	# Create new Conatiner mapping 
	$Job = New-AzureRmRecoveryServicesAsrProtectionContainerMapping -Name $ProtectionContainerMappingName -Policy $Policy -PrimaryProtectionContainer $PrimaryProtectionContainer -RecoveryProtectionContainer $RecoveryProtectionContainer
	#WaitForJobCompletion -JobId $Job.Name

	# Get container mapping
	$ProtectionContainerMapping = Get-AzureRmRecoveryServicesAsrProtectionContainerMapping -Name $ProtectionContainerMappingName -ProtectionContainer $PrimaryProtectionContainer
	Assert-NotNull($ProtectionContainerMapping)
	Assert-NotNull($ProtectionContainerMapping.Name)

	# Get primary network
	$PrimaryNetwork = Get-AzureRmRecoveryServicesAsrNetwork -Fabric $PrimaryFabric | where { $_.FriendlyName -eq $PrimaryNetworkFriendlyName}
	$RecoveryNetwork = Get-AzureRmRecoveryServicesAsrNetwork -Fabric $RecoveryFabric | where { $_.FriendlyName -eq $RecoveryNetworkFriendlyName}

	# Create network mapping
    $Job = New-AzureRmRecoveryServicesAsrNetworkMapping -Name $NetworkMappingName -PrimaryNetwork $PrimaryNetwork -RecoveryNetwork $RecoveryNetwork
	#WaitForJobCompletion -JobId $Job.Name

	# Get network mapping
	$NetworkMapping = Get-AzureRmRecoveryServicesAsrNetworkMapping -Name $NetworkMappingName -Network $PrimaryNetwork

	# Get protectable item
	$protectable = Get-AzureRmRecoveryServicesAsrProtectableItem -ProtectionContainer $PrimaryProtectionContainer -FriendlyName $VMName
	Assert-NotNull($protectable)
	Assert-NotNull($protectable.Name)

	# New replication protected item
	$Job = New-AzureRmRecoveryServicesAsrReplicationProtectedItem -ProtectableItem $protectable -Name $protectable.Name -ProtectionContainerMapping $ProtectionContainerMapping
	#WaitForJobCompletion -JobId $Job.Name
	#WaitForIRCompletion -VM $protectable 
	Assert-NotNull($Job)

	# Get replication protected item
	$protected = Get-AzureRmRecoveryServicesAsrReplicationProtectedItem -ProtectionContainer $PrimaryProtectionContainer -Name $protectable.Name
	Assert-NotNull($protected)
	Assert-NotNull($protected.Name)

	# Remove protected item
	$Job = Remove-AzureRmRecoveryServicesAsrReplicationProtectedItem -ReplicationProtectedItem $protected
	#WaitForJobCompletion -JobId $Job.Name
	$protected = Get-AzureRmRecoveryServicesAsrReplicationProtectedItem -ProtectionContainer $PrimaryProtectionContainer | Where-Object {$_.Name -eq $protectable.Name} 
	Assert-Null($protected)

	# Remove network mapping
	$Job = Remove-AzureRmRecoveryServicesAsrNetworkMapping -NetworkMapping $NetworkMapping
	#WaitForJobCompletion -JobId $Job.Name

	# Remove conatiner mapping
	$Job = Remove-AzureRmRecoveryServicesAsrProtectionContainerMapping -ProtectionContainerMapping $ProtectionContainerMapping
	#WaitForJobCompletion -JobId $Job.Name
	$ProtectionContainerMapping = Get-AzureRmRecoveryServicesAsrProtectionContainerMapping -ProtectionContainer $PrimaryProtectionContainer | Where-Object {$_.Name -eq $ProtectionContainerMappingName}
	Assert-Null($ProtectionContainerMapping)

	# Remove Policy
	$Job = Remove-AzureRmRecoveryServicesAsrPolicy -Policy $Policy
	#WaitForJobCompletion -JobId $Job.Name
	$Policy = Get-AzureRmRecoveryServicesAsrPolicy | Where-Object {$_.Name -eq $PolicyName}
	Assert-Null($Policy)
}
