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

#version 0.5
#requires -module azurerm
#requires -runasadministrator

#Importing module for the script to work
Import-Module azurerm
Write-output "Imported AzureRM module..."

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

function Get-Menu {
    param(
        $subscription_list,
        $resourcegroup_list,
        $resource_list
    )
    $Type = $false
    $i = 0
    #Create the list for Subscription
    if($subscription_list){
        $resource = $subscription_list
        $name = 'SubscriptionName'
        $ID = 'SubscriptionID'
        }

    #Create the list for ResourceGroupName
    if($resourcegroup_list){
        $resource = $resourcegroup_list
        $name = 'ResourceGroupName'
        $ID = 'ResourceId'
        }

    #Create the list for resources
    if($resource_list){
        $resource = $resource_list
        $name = 'ResourceName'
        $ID = 'ResourceId'
        $Type = $true
        }
    
    #Create the Menu    
    $resource | ForEach-Object{
        $i++
        if(!$Type){
            [PSCustomObject]@{Option = $i
                              $name = $_.$name
                              $ID = $_.$ID
                              } 
        }else{
                      [PSCustomObject]@{Option = $i
                              $name = $_.$name
                              $ID = $_.$ID
                              Type = ($($_.ResourceType).split('.'))[1]
                              }   
        }       
    }
    [PSCustomObject]@{Option = "R"
                      $name = "Return to Menu"
                      $ID = ''}        

} #End Get-Menu

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
    param( $list )
    
    if($list){
        #$access_list_subs | sort objecttype | ft -AutoSize
        $list | Out-GridView
        #Get the option to export the list to file
        [string]$export_choice = read-host "Do you want to export to CSV? Y/N"

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
    
    #Create the menu for all the subscriptions
    $sub_menu = Get-Menu -subscription_list $Sub_list
    $sub_menu | select option,Subscriptionname | ft

    #Get subscription option
    $option = Read-Host "Choose an option"
    
    if($option -eq 'r'){break}

    if([int32]$option -le $($sub_menu.count-1)){
        Clear-Host
        
        #Match the option to the subscitpion name to be used in permission function
        $sub_name = $sub_menu | Where-Object {$_.option -eq $option}
        
        Write-Output "Getting access for subscription: $($sub_name.SubscriptionName)   Please wait..."  
        
        #Geting the access permisions for subscription
        $access_list_subs = Get-ArmPermission_Access -Sub_name $sub_name
        
        Display-Results -list $access_list_subs

    }
} #End Option-Two

function Option-Three{ #"3. Individual resource group"
    param( $Sub_list )
    
    #Create the menu for all the subscriptions
    $sub_menu = Get-Menu -subscription_list $Sub_list
    $sub_menu | select option,Subscriptionname | ft
    
    #Get subscription option
    $option = Read-Host "Choose an option"

    if($option -eq 'r'){break}

    if([int32]$option -le $($sub_menu.count-1)){
        Clear-Host
        
        #Match the option to the subscitpion name to be used in permission function
        $sub_name = $sub_menu | Where-Object {$_.option -eq $option}
        
        Write-Output "Connecting to subscription: $($sub_name.Subscriptionname)"
        
        #Connect to the subscription
        $tenant = Set-AzureRmContext -SubscriptionId $sub_name.SubscriptionId | Out-Null
        
        #Get all the resource groups
        $ResourceGroups = Get-AzureRmResourceGroup

        #Create Menu
        $res_group_menu = Get-Menu -resourcegroup_list $ResourceGroups
        
        do{   
            $get_back = $false
            Clear-Host
            Write-Output "Connected to subscription: $($sub_name.Subscriptionname)"  
            Write-Output "Logged in as: $user"
            
            #List rsource groups
            $res_group_menu | select option,ResourceGroupName | ft

            #Get ResourceGroup option
            $option = Read-Host "Choose an option"
        
            if($option -eq 'r'){break}

            if([int32]$option -le $($res_group_menu.count-1)){
                            
                    Clear-Host
                    #Match the option to the resouorce group name to be used to retrive permission
                    $res_group_menu = $res_group_menu | Where-Object {$_.option -eq $option}
        
                    Write-Output "Getting access for resource group: $($res_group_menu.ResourceGroupName)   Please wait..."  
        
                    #Geting resources for this subscription
                    $access_list_resgroup = Get-ArmPermission_Access -sub_name $sub_name -resgroup_name $res_group_menu
        
                    Display-Results -list $access_list_resgroup

                    $get_back = $true
            }else{

                Write-Warning 'Inputed number outside the option'
                $choose = Read-Host 'Do you want to try again: Y/N'
                
                if($choose -eq 'Y'){$get_back = $false}else{$get_back = $true}
            }
            

        }until($get_back)

    }

} #End Option-Three

function Option-Four{ # "4. Individual resource"
    param( $Sub_list )

    #Create the menu for all the subscriptions
    $sub_menu = Get-Menu -subscription_list $Sub_list
    $sub_menu | Select-Object option,Subscriptionname | Format-Table
    
    #Get subscription option
    $option = Read-Host "Choose an option"

    if($option -eq 'r'){break}

    if([int32]$option -le $($sub_menu.count-1)){
        Clear-Host
        
        #Match the option to the subscitpion name to be used in permission function
        $sub_name = $sub_menu | Where-Object {$_.option -eq $option}
        
        Write-Output "Connecting to subscription: $($sub_name.Subscriptionname)"
        #Connect to the subscription
        Set-AzureRmContext -SubscriptionId $sub_name.SubscriptionId | Out-Null
        
        Write-Output "Collecting all the resource groups for $($sub_name.SubscriptionName)"
        $ResourceGroups = Get-AzureRmResourceGroup

        #Create Menu for resource groups
        $res_group_menu = Get-Menu -resourcegroup_list $ResourceGroups
        
        do{
            $get_back = $false
            Clear-host 
            
            $res_group_menu | Select-Object option,ResourceGroupName | Format-Table

            #Get ResourceGroup option
            $option = Read-Host "Choose an option"
            
            if($option -eq 'r'){break}

            if([int32]$option -le $($res_group_menu.count-1)){
                Clear-Host
            
                #Match the option to the resouorce group name to be used to retrive permission
                $res_group_menu = $res_group_menu | Where-Object {$_.option -eq $option}
                
                Write-Output "Getting resources for resource group : $($res_group_menu.ResourceGroupName)   Please wait..."  
                
                $resource_list = Find-AzureRmResource -ResourceGroupNameEquals $res_group_menu.ResourceGroupName

                $res_menu = Get-Menu -resource_list $resource_list
                do{ 
                    Clear-Host
                    $get_back = $false
                    $res_menu | Select-Object option,ResourceName,type | Format-Table
                    
                    #Get resource option
                    $option = Read-Host "Choose an option"

                    if($option -eq 'r'){break}

                    if([int32]$option -le $($res_menu.count-1)){
                        Clear-Host
                
                        #Match the option to the resouorce group name to be used to retrive permission
                        $res_name = $res_menu | Where-Object {$_.option -eq $option}
                    
                        Write-Output "Getting access permissions for resource : $($res_name.ResourceName)   Please wait..." 
                        
                        #Geting resources for this subscription
                        $access_list_res = Get-ArmPermission_Access -sub_name $sub_name -resgroup_name $res_group_name -resource $res_name
                    
                        Display-Results -list $access_list_res
                        
                        $get_back = $true
                    }else{
                        Write-Warning 'Inputed number outside the option'
                        $choose = Read-Host 'Do you want to try again: Y/N'
                        
                        if($choose -eq 'Y'){$get_back = $false}else{$get_back = $true}
                    }
                }until($get_back)

                $get_back = $true

            }else{
                Write-Warning 'Inputed number outside the option'
                $choose = Read-Host 'Do you want to try again: Y/N'

                if($choose -eq 'Y'){$get_back = $false}else{$get_back = $true}
            }

        }until($get_back)
    }

} #End Option-Four

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
            Get-AzureRmRoleAssignment -SignInName $user -ErrorAction stop | Out-Null
            
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


#Main Code
do{
    try{
    
        try{
        Write-output "Checking Azure connection..."
        
        #Check if the connection to the Azure is established
        $user = (Get-AzureRmContext).Account.id
        if (!$user){throw}   
        
        Write-output "Connection to Azure tenant has been established"

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
                         #"6. Get changes to access permisions in specific date range";
                         #"7. All resource groups in subscription";
                         #"8. All resources in subscription";
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
            }

        }until ($option -eq "x")

    }
    catch{
        Write-Output "Could not get any subscriptions. "
        $exit = Read-Host "Do you want to try again? Y/N"
        if($exit -eq "N"){
            $option = "x"
            Write-Warning 'Script Ended'
        }
    }
}until($option -eq "x") #End of Main
