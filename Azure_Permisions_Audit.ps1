# #############################################################################
# COMPANY INC - SCRIPT - POWERSHELL
# NAME: Azure_Permisions_Audit.ps1
# 
# AUTHOR:  Marek Cielniaszek
# DATE:  2017/06/19
# EMAIL: cielniaszek.marek@gmail.com
# 
# COMMENT:  Script will log you in to the Azure ARM platform and it will work on the subscriptions,resource groups and resources.
#           You will be presented with a Menu after login to azure.
#
# VERSION HISTORY
# 0.1 2017.05.17 Initial Version option 1,2
# 0.2 2017.05.28 Upgrade with option 3
# 0.3 2017.06.01 Added option 4,5
# 0.4 2017.06.16 Fix bugs and added CSV exports
# 0.5 2017.06.19 Added type on the resourse menu
# 0.6 2017.06.20 Replaced module azurerm with azurerm.profile and azurerm.resources to speed up loading time
# 0.7 2017.06.22 Removed Get-Menu functions and replaced it with Out-Gridview input option. Added requirement for powershell version 3.0
# 0.8 2017.06.26 Added mutiple group members retrival to one out-gridview
# 0.9 Added Option 6 to display Azure RBAC role definitions
# 1.0 Added Option 7 to display changes to permission in the specific time frame
# 1.1 Added option to display all RBAC roles for all the subscriptions, also minor bug fixes
#
# #############################################################################

<#
.SYNOPSIS
Azure_Permisions_audit.ps1 is build to enable quick way to understand the permisions that have been assigned in the Azure ARM platform 

.DESCRIPTION
Script will log you in to the Azure ARM platform and it will work on the subscriptions,resource groups and resources.
You will be presented with a Menu after login to azure.

Logged in as: user@contoso.onmicrosoft.com
Choose option to list access permision for:

1. All the subscriptions in ARM platform
2. Individual subscription
3. Individual resource group
4. Individual resource
5. Search for user access permision across all subscriptions
6. Display RBAC permision roles and definitions for specific subscription
7. Display RBAC permision roles and definitions for all subscriptions
8. Get changes to access permisions between 1 and max 14 days
X. Exit               

Select option number: 

After each option you will be presented with the list of permision in a Out-Gridview windows.
There is also an option to export permisions to CSV file after each permission output.

.EXAMPLE
.\Azure_Permisions_audit.ps1 

.NOTES
Script will start slow as it loads azurerm module
It has been tested on the module azurerm -version 4.0.2
The Script need to be executed as a local administrator but this functionality can be removed if needed for the service desk.
Just remove #require -runasadministrator

The reason for the local admin check is to indetify if the Set-ExecutionPolicy can be changed. This script does not change any settings

#>

#version 1.0
#Requires -Version 3.0
#equires -runasadministrator
#Requires -Modules AzureRM.Profile, @{ModuleName="AzureRM.Resources";ModuleVersion="4.1.0"}


#Importing module for the script to work
Import-Module AzureRM.Profile
Write-output "Imported AzureRM.Profile module..."
Import-Module AzureRM.Resources
Write-output "Imported AzureRM.Resources module..."

Function Get-ArmSubscription_Access {
    param(
        [Parameter(Mandatory=$true)]
        $subs
    )
    #Reset progress bar count
    $i = 0
    
    #Loop through all the subscriptions 
    $subs | ForEach-Object {
        
        #Progress bar counter
        $i++
        $subname = $_.SubscriptionName
        
        Write-Progress -Activity "Retreiving Subscription info" -PercentComplete (($i/$Subs.count)*100) -Status "Ramaining $($Subs.count-$($i-1))"
        
        #Get permisions for all subscriptions
        Get-AzureRmRoleAssignment -Scope $("/subscriptions/"+$_.SubscriptionId) | ForEach-Object{
            
            #Create object with all the details
            [PsCustomObject] @{
                    Subscription = $Subname
                    Displayname = $_.DisplayName
                    Role = $_.RoleDefinitionName
                    ObjectType = $_.ObjectType
                    Scope = $_.scope
                }
            }
    
        }
    #Remove progress bar
    Write-Progress -Activity "Retreiving Subscription info" -Completed
 
} #End Get-ArmSubscription_Access

function Get-ArmPermission_Access{
    param(
        [Parameter(Mandatory=$true)]$sub_name,
        $resgroup_name,
        $resource       
    )
       
    #Get subscripitonID
    $sub_id = $sub_name.SubscriptionID
    $scope_path = $("/subscriptions/"+$Sub_Id)

    #Change the scope path if resource group is selected
    if($resgroup_name -and !($resource)){
        $scope_path = $("/subscriptions/"+$Sub_Id+"/resourceGroups/"+$($resgroup_name.ResourceGroupName))
    }

    #Change the scope path if resource is selected
    if($resource){
        $scope_path = $resource.ResourceId
    }
    
    #Get access permisions for specific resource
    Get-AzureRmRoleAssignment -Scope $scope_path | ForEach-Object {
        
        #Clear variables
        $scope = $null
        $inherited = $null
        $level = $null

        #Select inheritence output
        if($scope_path -eq $_.scope){
            $inherited = 'N/A'
            $level = 'N/A'
            $scope = 'This Resource'
        
        }else{ 
            $scope = 'Inherited' 
            if(($_.scope.Split('/')).count -gt 3 -and ($_.scope.Split('/')).count -lt 6){
            
                $inherited = $_.Scope.split('/')[4]
                $level = 'Resource Group' 

            }else{ 
                $inherited = $sub_name.SubscriptionName
                $level = 'Subscription'
            }
        }

        #Create the object
        [PSCustomObject]@{
            Displayname = $_.DisplayName
            Role = $_.RoleDefinitionName
            ObjectType = $_.ObjectType
            Scope = $scope
            Level = $level
            InheritedFrom = $inherited
            
        }
    }   

} # End Get-ArmResourceGroup_Access

function Get-ArmAccessForUser {
    param(
        $username,
        $subscriptionid
    )
    
    
    #Set to current subscription
    Set-AzureRmContext -Subscriptionid $subscriptionid | Out-Null 

    #Getting all the permisions for this user
    Get-AzureRmRoleAssignment -SignInName $username -ExpandPrincipalGroups | ForEach-Object {
        
        #Get subscriptionID
        $subid = $_.Scope.split('/')[2]

        #Get Resource group name
        $ResourceGroup = $_.Scope.split('/')[4]

        #Get Resource name
        $Resource = ($($_.scope).split('/')[6]),($($_.scope).split('/')[7]),($($_.scope).split('/')[8]) -join ('/')
        
        #If resourcegroup or resource not defined insert N/A
        if($ResourceGroup -eq $null){$ResourceGroup = 'N/A'}
        if($Resource -eq '//'){$Resource = 'N/A'}
        
        #Create the object
        [PsCustomObject]@{DisplayName = $_.DisplayName
                          ObjectType = $_.ObjectType
                          Signin = $_.SignInName
                          Role = $_.RoleDefinitionName
                          Subscription = ($subscriptions | where-object {$_.SubscriptionId -eq $subid}).SubscriptionName
                          ResourceGroup = $ResourceGroup
                          Resource = $Resource}
    }

} #End Get-ArmAccessForUser 

function Show-SaveFileDialog{
  param(
    $StartFolder = [Environment]::GetFolderPath('MyDocuments'),
    $Title = 'Export to file',
    $Filter = 'csv|*.csv|All|*.*|Scripts|*.ps1|Texts|*.txt|Logs|*.log'
  )
  
  Add-Type -AssemblyName PresentationFramework
  
  #Create the form
  $dialog = New-Object -TypeName System.Windows.Forms.SaveFileDialog
  
  #Adding the properties
  $dialog.title = $Title
  $dialog.initialdirectory = $StartFolder
  $dialog.Filter = $Filter
  
  #Saving the selected path
  $resultat = $dialog.ShowDialog()
  
  #Return value
  if ($resultat){$dialog.FileName}

} #End Show-SaveFileDialog

function Export-output {
    param(
        [Parameter(Mandatory=$true)]
         $csv
    )
    process{
    
        #Display explorer dialog box to save file   
        $filepath = Show-SaveFileDialog
        if($filepath){
            #Export to specified path
            $csv | export-csv -Path $filepath -NoTypeInformation
            Write-Output "Export finished to $filepath"
            Write-Output 'You will return to main menu in 3 sec.'
            sleep -Seconds 3
        }else{
            Write-Warning 'No file specified. No export done'
            Write-Output 'You will return to main menu in 5 sec.'
            Sleep -Seconds 5
        }

    }

} #End Export-output

function Display-Results{
    param( $list,$TitleBar )
    
    if($list){
        
        while($true){
            
            #Display menu
            $option_group = $list | Out-GridView -Title $($TitleBar+"            Loged in as: "+$user) -OutputMode Multiple
            
            if(!$Option_group){break}


            $user_list = $option_group | ForEach-Object {
                
                $group_name = $_.Displayname 

                if( $_.ObjectType -eq 'Group'){
                    #Retreving all users from the group
                    Get-AzureRmADGroupMember -GroupObjectId $((Get-AzureRmADGroup -SearchString $_.Displayname).id.guid) | select * | foreach {
                            [PSCustomObject]@{DisplayName = $_.DisplayName
                                              LoginName = $_.userprincipalname
                                              Type = $_.type
                                              MemberOf = $group_name}
                        }
                
            
                }else{ Write-Warning "'$($_.Displayname)' is not a group therefore can not retrive members" }

            }

            if($User_list){
                
                #Display all the members for all the groups selected
                $User_list | Out-GridView -Title $("Group members            Loged in as: "+$user)

            }else{ Write-Warning "No users in group $($group_name)" }
                            
        }
        #Get the option to export the list to file
        [string]$export_choice = read-host "Do you want to export permissions to CSV? Y/N"

        #If option yes then export to file using Export-Output function
        if($export_choice -eq "y"){Export-output -csv $list}

    }else{ Warning-Message -time 10 }

} #End Display-Results

function Warning-Message {
    param( $time )

    Write-Warning 'No permisions have been retrieved. This means no access is given to read permisions for subscriptions:'
    Write-Output "You will return to main menu in $time sec."
    Sleep -Seconds $time

} #End Warning-Message

function Get-AzureRmAuthorizationChangeLog { 
<#

.SYNOPSIS

Gets access change history for the selected subscription for the specified time range i.e. role assignments that were added or removed, including classic administrators (co-administrators and service administrators).
Maximum duration that can be queried is 15 days (going back up to past 90 days).


.DESCRIPTION

The Get-AzureRmAuthorizationChangeLog produces a report of who granted (or revoked) what role to whom at what scope within the subscription for the specified time range. 

The command queries all role assignment events from the Insights resource provider of Azure Resource Manager. Specifying the time range is optional. If both StartTime and EndTime parameters are not specified, the default query interval is the past 1 hour. Maximum duration that can be queried is 15 days (going back up to past 90 days).


.PARAMETER StartTime 

Start time of the query. Optional.


.PARAMETER EndTime 

End time of the query. Optional


.EXAMPLE 

Get-AzureRmAuthorizationChangeLog

Gets the access change logs for the past hour.


.EXAMPLE   

Get-AzureRmAuthorizationChangeLog -StartTime "09/20/2015 15:00" -EndTime "09/24/2015 15:00"

Gets all access change logs between the specified dates

Timestamp        : 2015-09-23 21:52:41Z
Caller           : admin@rbacCliTest.onmicrosoft.com
Action           : Revoked
PrincipalId      : 54401967-8c4e-474a-9fbb-a42073f1783c
PrincipalName    : testUser
PrincipalType    : User
Scope            : /subscriptions/9004a9fd-d58e-48dc-aeb2-4a4aec58606f/resourceGroups/TestRG/providers/Microsoft.Network/virtualNetworks/testresource
ScopeName        : testresource
ScopeType        : Resource
RoleDefinitionId : /subscriptions/9004a9fd-d58e-48dc-aeb2-4a4aec58606f/providers/Microsoft.Authorization/roleDefinitions/b24988ac-6180-42a0-ab88-20f7382dd24c
RoleName         : Contributor


.EXAMPLE 

Get-AzureRmAuthorizationChangeLog  -StartTime ([DateTime]::Now - [TimeSpan]::FromDays(5)) -EndTime ([DateTime]::Now) | FT Caller, Action, RoleName, PrincipalName, ScopeType

Gets access change logs for the past 5 days and format the output

Caller                  Action                  RoleName                PrincipalName           ScopeType
------                  ------                  --------                -------------           ---------
admin@contoso.com       Revoked                 Contributor             User1                   Subscription
admin@contoso.com       Granted                 Reader                  User1                   Resource Group
admin@contoso.com       Revoked                 Contributor             Group1                  Resource

.LINK

New-AzureRmRoleAssignment

.LINK

Get-AzureRmRoleAssignment

.LINK

Remove-AzureRmRoleAssignment

#>

    [CmdletBinding()] 
    param(  
        [parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$true, HelpMessage = "The start time. Optional
             If both StartTime and EndTime are not provided, defaults to querying for the past 1 hour. Maximum allowed difference in StartTime and EndTime is 15 days")] 
        [DateTime] $StartTime,

        [parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$true, HelpMessage = "The end time. Optional. 
            If both StartTime and EndTime are not provided, defaults to querying for the past 1 hour. Maximum allowed difference in StartTime and EndTime is 15 days")] 
        [DateTime] $EndTime
    ) 
    PROCESS { 
         # Get all events for the "Microsoft.Authorization" provider by calling the Insights commandlet
         $events = Get-AzureRmLog -ResourceProvider "Microsoft.Authorization" -DetailedOutput -StartTime $StartTime -EndTime $EndTime
             
         $startEvents = @{}
         $endEvents = @{}
         $offlineEvents = @()

         # StartEvents and EndEvents will contain matching pairs of logs for when role assignments (and definitions) were created or deleted. 
         # i.e. A PUT on roleassignments will have a Start-End event combination and a DELETE on roleassignments will have another Start-End event combination
         $startEvents = $events | ? { $_.httpRequest -and $_.Status -ieq "Started" }
         $events | ? { $_.httpRequest -and $_.Status -ne "Started" } | % { $endEvents[$_.OperationId] = $_ }
         # This filters non-RBAC events like classic administrator write or delete
         $events | ? { $_.httpRequest -eq $null } | % { $offlineEvents += $_ } 

         $output = @()

         # Get all role definitions once from the service and cache to use for all 'startevents'
         $azureRoleDefinitionCache = @{}
         Get-AzureRmRoleDefinition | % { $azureRoleDefinitionCache[$_.Id] = $_ }

         $principalDetailsCache = @{}

         # Process StartEvents
         # Find matching EndEvents that succeeded and relating to role assignments only
         $startEvents | ? { $endEvents.ContainsKey($_.OperationId) `
             -and $endEvents[$_.OperationId] -ne $null `
             -and $endevents[$_.OperationId].OperationName.StartsWith("Microsoft.Authorization/roleAssignments", [System.StringComparison]::OrdinalIgnoreCase)  `
             -and $endEvents[$_.OperationId].Status -ieq "Succeeded"} |  % {
       
         $endEvent = $endEvents[$_.OperationId];
        
         # Create the output structure
         $out = "" | select Timestamp, Caller, Action, PrincipalId, PrincipalName, PrincipalType, Scope, ScopeName, ScopeType, RoleDefinitionId, RoleName

         $out.Timestamp = Get-Date -Date $endEvent.EventTimestamp -Format u
         $out.Caller = $_.Caller
         if ($_.HttpRequest.Method -ieq "PUT") {
            $out.Action = "Granted"
            if ($_.Properties.Content.ContainsKey("requestbody")) {
                $messageBody = ConvertFrom-Json $_.Properties.Content["requestbody"]
            }
             
          $out.Scope =  $_.Authorization.Scope
        } 
        elseif ($_.HttpRequest.Method -ieq "DELETE") {
            $out.Action = "Revoked"
            if ($endEvent.Properties.Content.ContainsKey("responseBody")) {
                $messageBody = ConvertFrom-Json $endEvent.Properties.Content["responseBody"]
            }
        }

        if ($messageBody) {
            # Process principal details
            $out.PrincipalId = $messageBody.properties.principalId
            if ($out.PrincipalId -ne $null) { 
				# Get principal details by querying Graph. Cache principal details and read from cache if present
				$principalId = $out.PrincipalId 
                
				if($principalDetailsCache.ContainsKey($principalId)) {
					# Found in cache
                    $principalDetails = $principalDetailsCache[$principalId]
                } else { # not in cache
		            $principalDetails = "" | select Name, Type
                    $user = Get-AzureRmADUser -ObjectId $principalId
                    if ($user) {
                        $principalDetails.Name = $user.DisplayName
                        $principalDetails.Type = "User"    
                    } else {
                        $group = Get-AzureRmADGroup -ObjectId $principalId
                        if ($group) {
                            $principalDetails.Name = $group.DisplayName
                            $principalDetails.Type = "Group"        
                        } else {
                            $servicePrincipal = Get-AzureRmADServicePrincipal -objectId $principalId
                            if ($servicePrincipal) {
                                $principalDetails.Name = $servicePrincipal.DisplayName
                                $principalDetails.Type = "Service Principal"                        
                            }
                        }
                    }              
					# add principal details to cache
                    $principalDetailsCache.Add($principalId, $principalDetails);
	            }

                $out.PrincipalName = $principalDetails.Name
                $out.PrincipalType = $principalDetails.Type
            }

			# Process scope details
            if ([string]::IsNullOrEmpty($out.Scope)) { $out.Scope = $messageBody.properties.Scope }
            if ($out.Scope -ne $null) {
				# Remove the authorization provider details from the scope, if present
			    if ($out.Scope.ToLower().Contains("/providers/microsoft.authorization")) {
					$index = $out.Scope.ToLower().IndexOf("/providers/microsoft.authorization") 
					$out.Scope = $out.Scope.Substring(0, $index) 
				}

              	$scope = $out.Scope 
				$resourceDetails = "" | select Name, Type
                $scopeParts = $scope.Split('/', [System.StringSplitOptions]::RemoveEmptyEntries)
                $len = $scopeParts.Length

                if ($len -gt 0 -and $len -le 2 -and $scope.ToLower().Contains("subscriptions"))	{
                    $resourceDetails.Type = "Subscription"
                    $resourceDetails.Name  = $scopeParts[1]
                } elseif ($len -gt 0 -and $len -le 4 -and $scope.ToLower().Contains("resourcegroups")) {
                    $resourceDetails.Type = "Resource Group"
                    $resourceDetails.Name  = $scopeParts[3]
                    } elseif ($len -ge 6 -and $scope.ToLower().Contains("providers")) {
                        $resourceDetails.Type = "Resource"
                        $resourceDetails.Name  = $scopeParts[$len -1]
                        }
                
				$out.ScopeName = $resourceDetails.Name
                $out.ScopeType = $resourceDetails.Type
            }

			# Process Role definition details
            $out.RoleDefinitionId = $messageBody.properties.roleDefinitionId
			
            if ($out.RoleDefinitionId -ne $null) {
								
				#Extract roleDefinitionId Guid value from the fully qualified id string.
				$roleDefinitionIdGuid= $out.RoleDefinitionId.Substring($out.RoleDefinitionId.LastIndexOf("/")+1)

                if ($azureRoleDefinitionCache[$roleDefinitionIdGuid]) {
                    $out.RoleName = $azureRoleDefinitionCache[$roleDefinitionIdGuid].Name
                } else {
                    $out.RoleName = ""
                }
            }
        }
        $output += $out
    } # start event processing complete

    # Filter classic admins events
    $offlineEvents | % {
        if($_.Status -ne $null -and $_.Status -ieq "Succeeded" -and $_.OperationName -ne $null -and $_.operationName.StartsWith("Microsoft.Authorization/ClassicAdministrators", [System.StringComparison]::OrdinalIgnoreCase)) {
            
            $out = "" | select Timestamp, Caller, Action, PrincipalId, PrincipalName, PrincipalType, Scope, ScopeName, ScopeType, RoleDefinitionId, RoleName
            $out.Timestamp = Get-Date -Date $_.EventTimestamp -Format u
            $out.Caller = "Subscription Admin"

            if($_.operationName -ieq "Microsoft.Authorization/ClassicAdministrators/write"){
                $out.Action = "Granted"
            } 
            elseif($_.operationName -ieq "Microsoft.Authorization/ClassicAdministrators/delete"){
                $out.Action = "Revoked"
            }

            $out.RoleDefinitionId = $null
            $out.PrincipalId = $null
            $out.PrincipalType = "User"
            $out.Scope = "/subscriptions/" + $_.SubscriptionId
            $out.ScopeType = "Subscription"
            $out.ScopeName = $_.SubscriptionId
                                
            if($_.Properties -ne $null){
                $out.PrincipalName = $_.Properties.Content["adminEmail"]
                $out.RoleName = "Classic " + $_.Properties.Content["adminType"]
            }
                     
            $output += $out
        }
    } # end offline events

    $output | Sort Timestamp
    } 
} # End commandlet

function Option-One { #"1. All the subscriptions in ARM platform"
    param( $Sub_list )

    #Get the access list for all the subscriptions
    $access_list = Get-ArmSubscription_Access -subs $sub_list
    
    Display-Results -list $access_list

} #End Option-One 

function Option-Two { # "2. Individual subscription"
    param(
       $Sub_list
    )
    
    $option = $false
    
    #Create the menu for all the subscriptions 
    $TitleBar = "Connected as: $($user)"   
    $option = $sub_list | select Subscriptionname,SubscriptionId | sort SubscriptionName | Out-GridView -Title $TitleBar -OutputMode Single
    
    if(!$option){break}

    Clear-Host    
    
    Write-Output "Getting access for subscription: $($option.SubscriptionName)   Please wait..."  
    
    #Geting the access permisions for subscription
    $access_list_subs = Get-ArmPermission_Access -Sub_name $option
    
    Display-Results -list $access_list_subs -TitleBar "Access permisions for Subscription: $($option.SubscriptionName)"

 #   }
} #End Option-Two

function Option-Three{ #"3. Individual resource group"
    param( $Sub_list )
    
    $option = $false

    #Create the menu for all the subscriptions
    $TitleBar = "Connected as: $($user)" 
    $option = $sub_list | select Subscriptionname,SubscriptionId | sort SubscriptionName | Out-GridView -Title $TitleBar -OutputMode Single
    
    #Get subscription option

    if($option -eq 'r'){break}

    Clear-Host
    
    Write-Output "Connecting to subscription: $($option.SubscriptionName)   Please wait..."  
    
    #Connect to the subscription
    $tenant = Set-AzureRmContext -SubscriptionId $option.SubscriptionId | Out-Null
    
    #Get all the resource groups for thid subscription
    $ResourceGroups = Get-AzureRmResourceGroup             
    
    While($true){   
       Clear-Host
       $option_resgr = $false

       Write-Output "Connected to subscription: $($Option.Subscriptionname)"  
       
       #Get ResourceGroup option
       $TitleBar = "Connected as: $($user) / Subscription: $($option.SubscriptionName)"   
       $option_resgr = $ResourceGroups | select ResourceGroupName,Location,ProvisioningState | sort ResourceGroupName | Out-GridView -Title $TitleBar -OutputMode Single

       if(!$option_resgr){break}
                 
       Clear-Host 
             
       Write-Output "Getting access for resource group: $($option_resgr.ResourceGroupName)   Please wait..."  
    
       #Geting resources for this subscription
       $access_list_resgroup = Get-ArmPermission_Access -sub_name $Option -resgroup_name $option_resgr
    
       Display-Results -list $access_list_resgroup -TitleBar "Access permisions for Resource Group: $($option_resgr.ResourceGroupName)"
    
    }


} #End Option-Three

function Option-Four{ # "4. Individual resource"
    param( $Sub_list )
    
    $option = $false

    #Create the menu for all the subscriptions
    $TitleBar = "Connected as: $($user)" 
    $option = $sub_list | select Subscriptionname,SubscriptionId | sort SubscriptionName | Out-GridView -Title $TitleBar -OutputMode Single 

    if($option -eq 'r'){break}

    Clear-Host
    
    Write-Output "Connecting to subscription: $($option.SubscriptionName)   Please wait..."  
    
    #Connect to the subscription
    $tenant = Set-AzureRmContext -SubscriptionId $option.SubscriptionId | Out-Null
        
    While($true){   
       Clear-Host
       $option_resgr = $false
       Write-Output "Collecting Resource Groups for subscription: $($option.SubscriptionName)"
    
       #Get all the resource groups for thid subscription
       $ResourceGroups = Get-AzureRmResourceGroup             

       #Get ResourceGroup option
       $TitleBar = "Connected as: $($user) / Subscription: $($option.SubscriptionName)" 
       $option_resgr = $ResourceGroups | select ResourceGroupName,Location,ProvisioningState | sort ResourceGroupName | Out-GridView -Title $TitleBar -OutputMode Single

       if(!$option_resgr){break}
       
       while($true){
           
           $option_reslist = $false

           Write-Output "Collecting Resources for Resource Group $($option_resgr.ResourceGroupName)"
           $resource_list = Find-AzureRmResource -ResourceGroupNameEquals $option_resgr.ResourceGroupName


           ##Get Resources option
           $TitleBar = "Connected as: $($user) / Subscription: $($option.SubscriptionName) / Resource Group: $($option_resgr.ResourceGroupName)"   
           $option_reslist = $resource_list | select ResourceName,ResourceType,location,ResourceGroupName,ResourceID | sort ResourceName | Out-GridView -Title $TitleBar -OutputMode Single
           
           if(!$option_reslist){break}
           
           Write-Output "Getting access permissions for resource : $($option_reslist.ResourceName)   Please wait..." 
           
           #Geting resources for this subscription
           $access_list_res = Get-ArmPermission_Access -sub_name $option -resgroup_name $option_resgr -resource $option_reslist
    
           Display-Results -list $access_list_res -TitleBar "Access permisions for Resource: $($option_reslist.ResourceName)"

           Clear-Host
       }
    }
}

function Option-Five { #"5. Search for user access permision across all subscriptions"
    param(
       $sub_list
    )
    Do{
        #Progress bar reset count
        $i = 0

        #Get the username
        [string]$user = Read-host "Type the email address of the user"

        try{
            #Check if the users exist in Azure Ad
            if(Get-AzureRmADUser -UserPrincipalName $user | Out-Null){Throw 'No user found'}
                        
            #Go through the list of subscriptions
            $user_access = $sub_list | ForEach-Object {
                    
                    #Display Progress bar
                    $i++
                    Write-Progress -Activity "Retreiving user access from subscriptions" -PercentComplete (($i/$Sub_list.count)*100) -Status "Remaining subscriptions $($Sub_list.count-$($i-1))"
                    
                    Get-ArmAccessForUser -username $user -subscriptionid $_.SubscriptionId
                }
            #End progress bar
            Write-Progress -Activity "Retreiving Subscription info" -Completed
            
            #Display the list to the console
            #$user_access | sort Subscription | ft -AutoSize
            $user_access | Out-GridView

            #Export to CSV file option
            [string]$export_choice = read-host "Do you want to export to CSV? Y/N"
            
            #Run export command if option is yes.
            if($export_choice -eq "y"){
                Export-output -csv $user_access
                $option = 'N'
            }else{$option = 'N'}
        }
        Catch{
            
            Write-Warning 'User not found in Azure AD'
            $option = Read-Host 'Do you want to try again? Y/N'
        }
    }until($option -eq 'N')

} #End Option-Five

function Option-Six {
    param(
        $sub_list
    )
    $titlebar = "Select Subscription to retrieve Roles"
    $option = $sub_list | Select-Object subscriptionname,subscriptionId | sort SubscriptionName | Out-GridView -Title $TitleBar -OutputMode Single
        if(!$option){break}
    $Title_subname = $null

    $option | ForEach-Object {
        $Title_subname = $_.subscriptionName
        Set-AzureRmContext -Subscriptionid $_.subscriptionid | Out-Null
        $roles = Get-AzureRmRoleDefinition | select name, Description, iscustom
        
        while($true){
            $option_roles = $roles | Out-GridView -OutputMode Multiple -Title "All roles for subscription $($Title_subname)"
            if(!$option_roles){break}

            $option_roles | ForEach-Object {
                $role_name = $_.name
                (Get-AzureRmRoleDefinition $_.name).Actions | ForEach-Object {
            
                    [Pscustomobject]@{Definition = $_
                                    RoleName = $role_name
                                    Type = 'Action'}
        
                }
                (Get-AzureRmRoleDefinition $_.name).NotActions | ForEach-Object {
            
                    [Pscustomobject]@{Definition = $_
                                    RoleName = $role_name
                                    Type = 'NotAction'}
        
                } 
            } 
        }  
    } | Out-GridView -Title 'Role definitions6'

} #End Option-Six

function Option-Seven {
    param(
        $sub_list
    )
    Write-Output "Collecting all roles from all subscription. Please wait..."
    $i = 0
    $roles = $subscriptions | ForEach-Object {
        $i++
        $subname = $_.subscriptionname
        Set-AzureRmContext -Subscriptionid $_.subscriptionid | Out-Null
        Write-Progress -Activity "Retreiving Subscription info" -PercentComplete (($i/$subscriptions.count)*100) -Status "Ramaining $($subscriptions.count-$($i-1))"
        
        Get-AzureRmRoleDefinition | foreach {
            if($_.IScustom -eq $false){$subname = 'Global Rule'}
            [PSCustomObject]@{
                              name = $_.name
                              Description = $_.Description
                              IScustom = $_.IScustom
                              AssignableScopes = $_.AssignableScopes
                              Subscription = $subname
                              }  
        }
    }
    #Remove progress bar
    Write-Progress -Activity "Retreiving Subscription info" -Completed
        
    $result = $roles | ?{$_.iscustom -eq $false} | sort name -Unique
    $result += $roles | ?{$_.iscustom -eq $true}
    #$result | Out-GridView

    while($true){
        $option_roles = $result | Out-GridView -OutputMode Multiple -Title "All roles for subscription all subscription"
        if(!$option_roles){break}
    
        $option_roles | ForEach-Object {
            
            $role_name = $_.name
            $scopeid = ($_.AssignableScopes -split '/')[2]
            $scopepath = '{'+$_.AssignableScopes+'}'
            try{
                if($_.IScustom -eq $true){
                    $connection = Set-azurermcontext -subscriptionid $scopeid -ErrorAction stop 
                }
            
                
                (Get-AzureRmRoleDefinition $_.name).Actions | ForEach-Object {
        
                    [Pscustomobject]@{Definition = $_
                                    RoleName = $role_name
                                    Type = 'Action'}
    
                }
                (Get-AzureRmRoleDefinition $_.name).NotActions | ForEach-Object {
        
                    [Pscustomobject]@{Definition = $_
                                    RoleName = $role_name
                                    Type = 'NotAction'}
    
                } 
            }
            catch{
                $scopepth 
                [Pscustomobject]@{Definition = 'Problem with a subscription scope: '+$scopepath
                                    RoleName = $role_name
                                    Type = $null}
            }
        } | Out-GridView -Title 'Role definitions'
} 


} #End Option-Seven


function Option-Eight {
    param(
        $sub_list
    )
    $TitleBar = 'Select Subscription'
    $option = $sub_list | Select-Object subscriptionname,subscriptionId | sort SubscriptionName | Out-GridView -Title $TitleBar -OutputMode Multiple
        if(!$option){break}
    #Day range
    [int32]$days = Read-Host "Choose number of days between 1-14"
    
    #Set to current subscription
    $history = $option | foreach{
        #Connecting to Subscription
        Set-AzureRmContext -Subscriptionid $_.subscriptionid | Out-Null
        
        #Collect logs
        Write-host "Collecting Logs from "$_.subscriptionname
        Get-AzureRmAuthorizationChangeLog -StartTime ([DateTime]::Now - [TimeSpan]::FromDays($days)) -EndTime ([DateTime]::Now) | select Caller, Action, RoleName, PrincipalName, ScopeType, Timestamp, Scopename
        
    }
    if($history){
        $history | Out-GridView
    }else{
        Write-Output "No changes found"
        Read-Host "Press any key to return to menu"
    }
} #End of Option-Eight

#Main Code
do{
    try{
        
        try{
        Write-output "Checking Azure connection..."
        
        #Check if the connection to the Azure is established
        $user = (Get-AzureRmContext).Account.id
        if (!$user){
                throw
            }else{   
        
            Write-output "Connection to Azure tenant has been established"
            }
        }
        catch{
            Write-Output "Not connected to Azure"
            Write-Output "Please login to Azure"
            
            #Connect to Azure
            Login-AzureRmAccount
            $user = (Get-AzureRmContext).Account.id

        }

        write-output "Getting the list of the subscriptions with this login..."
        $subscriptions = Get-AzureRmSubscription -ErrorAction Stop
        
        #New Get-AzureRMSubscirption version 4.0.2 replaced the property type SubscriptionName and SubscriptionID with name,ID 
                                                                                       #this is to enable backwords compatibility
        if($(($subscriptions | Get-Member).name | Where-Object {$_ -eq 'name' -or $_ -eq 'id'})){
            $subscriptions = $subscriptions | ForEach-Object{
                [PSCustomObject]@{SubscriptionName = $_.Name
                                  SubscriptionID = $_.Id}
            }
        
        }

        
        Do {
            Clear-Host
            Write-Output "Logged in as: $user"
            Write-Output "Choose option to list access permision for:";
                         "";
                         "1. All the subscriptions in ARM platform";
                         "2. Individual subscription";
                         "3. Individual resource group";
                         "4. Individual resource";
                         "5. Search for user access permision across all subscriptions";
                         "6. Display RBAC permision roles and definitions for specific subscription"
                         "7. Display RBAC permision roles and definitions for all subscriptions"
                         "8. Get changes to access permisions between 1 and max 14 days";
                         #"8. All resource groups in subscription";
                         #"9. All resources in subscription";
                         "X. Exit";
                         ""

        
            $option = Read-Host "Select option number"
            Clear-Host
        
            Switch ($option){
                1 {Option-One -Sub_list $subscriptions}
                2 {Option-Two -Sub_list $subscriptions}
                3 {Option-Three -Sub_list $subscriptions} 
                4 {Option-Four -Sub_list $subscriptions}  
                5 {Option-Five -sub_list $subscriptions}
                6 {Option-Six -sub_list $subscriptions}
                7 {Option-Seven -sub_list $subscriptions}
                8 {Option-Eight -sub_list $subscriptions}
            }

        }until ($option -eq "x")

    }
    catch{
        Write-Output "Could not get any subscriptions or connection to Azure has failed."
        $exit = Read-Host "Do you want to try again? Y/N"
        if($exit -eq "N"){
            $option = "x"
            Write-Warning 'Script Ended'
        }
    }
}until($option -eq "x") #End of Main
