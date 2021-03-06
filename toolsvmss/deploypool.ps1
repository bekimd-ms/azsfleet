Param(
    [string] $vmPool,
    [int] $vmCount=1,
    [string] $vmOS="",
    [string] $vmSize="Standard_DS2", 
    [int] $vmDataDisks=1, 
    [int] $vmDataDiskGB=4,
    [string] $AdminUserName,
    [string] $AdminPassword,
    [string] $Site = $env:AZURESITE,
    [string] $ImageId = ""
)

$configfile = $env:AZFLEET_CONFIG
$config = get-content $configfile | ConvertFrom-Json
$rg = $config.resourcegroup

#first check if pool with this name already exists. If it does exit with error

$dn = $rg + $vmPool
$storageEndpointSuffix= ((Get-AzContext).Environment | Get-AzEnvironment).StorageEndpointSuffix
$templateFile = (".\templates\poolvmss." + $vmOS + ".json" )

if( $Site -eq "" ) {
    New-AzResourceGroupDeployment -Name $dn -ResourceGroupName $rg `
                                  -TemplateFile $templateFile `
                                  -StorageEndpointSuffix $storageEndpointSuffix -vmPool $vmPool `
                                  -vmCount $vmCount -vmSize $vmSize `
                                  -vmDataDiskCount $vmDataDisks -vmDataDiskSizeInGB $vmDataDiskGB `
                                  -adminUserName $AdminUserName -adminPassword $AdminPassword `
                                  -verbose
}
else {
    #modify the template for edge site
    $template = get-content ($templateFile) -raw | ConvertFrom-Json -Depth 32

    $edgeSiteParam = @{
        defaultValue = ""
        metadata = @{ 
            description = "Edge site location"
        }
        type = "string"
        }
    $template.parameters | Add-Member -Name "edgeSite" -value $edgeSiteParam -MemberType NoteProperty

    $extendedLocation = @{  
            type = "EdgeZone" 
            name = "[parameters('edgeSite')]" 
        }
    $excludedTypes = @('Microsoft.Network/networkSecurityGroups','Microsoft.Storage/storageAccounts','Microsoft.Compute/virtualMachines/extensions')
    $template.resources | %{  if( $_.type -notin $excludedTypes) {$_ | Add-Member -Name "extendedLocation" -value $extendedLocation -MemberType NoteProperty }}

    if( $imageId -ne "" ){
        $imageReference = @{
            id = "[parameters('imageId')]"
        }    
        $templateVMSS = $template.resources | where type -eq "Microsoft.Compute/virtualMachineScaleSets"
        $templateVMSS.properties.virtualMachineProfile.storageProfile.imageReference = $imageReference 
    }

    $templateFile = ".\tmp\poolvmss." + $vmOS + ".json"
    $template | ConvertTo-Json -depth 32 | set-content ( $templateFile )

    New-AzResourceGroupDeployment -Name $dn -ResourceGroupName $rg `
                                  -TemplateFile $templateFile `
                                  -StorageEndpointSuffix $storageEndpointSuffix -vmPool $vmPool `
                                  -vmCount $vmCount -vmSize $vmSize `
                                  -vmDataDiskCount $vmDataDisks -vmDataDiskSizeInGB $vmDataDiskGB `
                                  -adminUsername $AdminUserName -adminPassword $AdminPassword `
                                  -edgeSite $site `
                                  -imageId $ImageId `
                                  -verbose
}