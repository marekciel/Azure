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
#Requires -Version 3.0
#requires -runasadministrator
#requires -module AzureRM.Profile,AzureRM.Resources


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

        $list | Out-GridView  -Title $($TitleBar+"            Loged in as: "+$user)

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
        Write-Output "Could not get any subscriptions or connection to Azure has failed."
        $exit = Read-Host "Do you want to try again? Y/N"
        if($exit -eq "N"){
            $option = "x"
            Write-Warning 'Script Ended'
        }
    }
}until($option -eq "x") #End of Main
