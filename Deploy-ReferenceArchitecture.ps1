﻿#
# Deploy_ReferenceArchitecture.ps1
#
param(
  [Parameter(Mandatory=$true)]
  $SubscriptionId,

  [Parameter(Mandatory=$true)]
  $Location,
  
  [Parameter(Mandatory=$false)]
  [ValidateSet("Prepare", "Infrastructure", "ADDS", "Operational", "Post")]
  $Mode = "Prepare"
)

$ErrorActionPreference = "Stop"

$templateRootUriString = $env:TEMPLATE_ROOT_URI
if ($templateRootUriString -eq $null) {
  $templateRootUriString = "https://raw.githubusercontent.com/mspnp/template-building-blocks/master/"
}

if (![System.Uri]::IsWellFormedUriString($templateRootUriString, [System.UriKind]::Absolute)) {
  throw "Invalid value for TEMPLATE_ROOT_URI: $env:TEMPLATE_ROOT_URI"
}

Write-Host
Write-Host "Using $templateRootUriString to locate templates"
Write-Host

$templateRootUri = New-Object System.Uri -ArgumentList @($templateRootUriString)

$loadBalancerTemplate = New-Object System.Uri -ArgumentList @($templateRootUri, "templates/buildingBlocks/loadBalancer-backend-n-vm/azuredeploy.json")
$virtualNetworkTemplate = New-Object System.Uri -ArgumentList @($templateRootUri, "templates/buildingBlocks/vnet-n-subnet/azuredeploy.json")
$virtualMachineTemplate = New-Object System.Uri -ArgumentList @($templateRootUri, "templates/buildingBlocks/multi-vm-n-nic-m-storage/azuredeploy.json")
$dmzTemplate = New-Object System.Uri -ArgumentList @($templateRootUri, "templates/buildingBlocks/dmz/azuredeploy.json")
$nsgTemplate = New-Object System.Uri -ArgumentList @($templateRootUri, "templates/buildingBlocks/networkSecurityGroups/azuredeploy.json")
$virtualMachineExtensionsTemplate = New-Object System.Uri -ArgumentList @($templateRootUri, "templates/buildingBlocks/virtualMachine-extensions/azuredeploy.json")

# Local templates
$opsNetworkInfrastructureTemplate = [System.IO.Path]::Combine($PSScriptRoot, "templates\azure\ops-network-infrastructure\azuredeploy.json")
$vnetPeeringTemplate = [System.IO.Path]::Combine($PSScriptRoot, "templates\azure\vnetpeering\azuredeploy.json")
$mgmtVnetPeeringTemplate = [System.IO.Path]::Combine($PSScriptRoot, "templates\azure\vnetpeering-mgmt-vnet.json")

#Azure Quick Start template file
$applicationGatewayTemplate = New-Object System.Uri("https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/101-application-gateway-create/azuredeploy.json")

# Azure Parameter Files
#network infrastructure
$opsNetworkParametersFile  = [System.IO.Path]::Combine($PSScriptRoot, "parameters\azure\ops-network.parameters.json")
$azureMgmtVirtualNetworkParametersFile = [System.IO.Path]::Combine($PSScriptRoot, "parameters\azure\mgmt-vnet.parameters.json")
$operationalVnetPeeringParametersFile = [System.IO.Path]::Combine($PSScriptRoot, "parameters\azure\operational-vnet-peering.parameters.json")
$mgmtVnetPeeringParametersFile = [System.IO.Path]::Combine($PSScriptRoot, "parameters\azure\mgmt-vnet-peering.parameters.json")
$nsgParametersFile = [System.IO.Path]::Combine($PSScriptRoot, "parameters\azure\nsg-rules.parameters.json")
#aads
$azureAddsVirtualMachinesParametersFile = [System.IO.Path]::Combine($PSScriptRoot, "parameters\azure\virtualMachines-adds.parameters.json")
$azureCreateAddsForestExtensionParametersFile = [System.IO.Path]::Combine($PSScriptRoot, "parameters\azure\create-adds-forest-extension.parameters.json")
$azureAddAddsDomainControllerExtensionParametersFile = [System.IO.Path]::Combine($PSScriptRoot, "parameters\azure\add-adds-domain-controller.parameters.json")
$azureVirtualNetworkDnsParametersFile = [System.IO.Path]::Combine($PSScriptRoot, "parameters\azure\virtualNetwork-adds-dns.parameters.json")
#workloads
$mgmtVMJumpboxParametersFile  = [System.IO.Path]::Combine($PSScriptRoot, "parameters\azure\mgmt-virtualmachine.parameters.json")
$webLoadBalancerParametersFile = [System.IO.Path]::Combine($PSScriptRoot, "parameters\azure\loadBalancer-web.parameters.json")
$bizLoadBalancerParametersFile = [System.IO.Path]::Combine($PSScriptRoot, "parameters\azure\loadBalancer-biz.parameters.json")
$dataLoadBalancerParametersFile = [System.IO.Path]::Combine($PSScriptRoot, "parameters\azure\loadBalancer-data.parameters.json")
#postdeployment config
$azurenVmDomainJoinExtensionParametersFile = [System.IO.Path]::Combine($PSScriptRoot, "parameters\azure\vm-domain-join.parameters.json")
$azureVmEnableWindowsAuthExtensionParametersFile = [System.IO.Path]::Combine($PSScriptRoot, "parameters\azure\vm-enable-windows-auth.parameters.json")

# Azure ADDS Deployments
$azureNetworkResourceGroupName = "uk-official-networking-rg"
$workloadResourceGroupName = "uk-official-operaional-rg"
$addsResourceGroupName = "uk-official-adds-rg"

# Login to Azure and select your subscription
Login-AzureRmAccount -SubscriptionId $SubscriptionId  #| Out-Null



##########################################################################
# Deploy Vnet and VPN Infrastructure in cloud
##########################################################################

if ($Mode -eq "Infrastructure" -Or $Mode -eq "Prepare") {

    
	Write-Host "Creating Networking resource group..."
    $azureNetworkResourceGroup = New-AzureRmResourceGroup -Name $azureNetworkResourceGroupName -Location $Location

	# Deploy network infrastructure, VPN and App Gateway
    Write-Host "Deploying operations network, VPN and AppGateway infrastructure..."
    New-AzureRmResourceGroupDeployment -Name "ops-network-deployment" -ResourceGroupName $azureNetworkResourceGroup.ResourceGroupName `
           -TemplateFile $opsNetworkInfrastructureTemplate -TemplateParameterFile $opsNetworkParametersFile

	#Deploy Mgmt network
    Write-Host "Deploying management network infrastructure..."
    New-AzureRmResourceGroupDeployment -Name "mgmt-network-deployment" -ResourceGroupName $azureNetworkResourceGroup.ResourceGroupName `
           -TemplateUri $virtualNetworkTemplate.AbsoluteUri -TemplateParameterFile $azureMgmtVirtualNetworkParametersFile

	#Create VNet Peerings
	Write-Host "Deploying Operational VNet Peering to Mgmt VNet..."
	New-AzureRmResourceGroupDeployment -Name "ops-vnetpeer-deployment" -ResourceGroupName $azureNetworkResourceGroup.ResourceGroupName `
	-TemplateFile $vnetPeeringTemplate  -TemplateParameterFile $mgmtVnetPeeringParametersFile


	Write-Host "Deploying Mgmt VNet Peering to Operational VNet..."
	New-AzureRmResourceGroupDeployment -Name "mgmt-vnetpeer-deployment" -ResourceGroupName $azureNetworkResourceGroup.ResourceGroupName `
	-TemplateFile $vnetPeeringTemplate -TemplateParameterFile $operationalVnetPeeringParametersFile

	#Create NSGs for management VNET
	 Write-Host "Deploying NSGs"
	 New-AzureRmResourceGroupDeployment -Name "nsg-deployment" -ResourceGroupName $azureNetworkResourceGroupName.ResourceGroupName `
        -TemplateUri $nsgTemplate.AbsoluteUri -TemplateParameterFile $nsgParametersFile

}


############################################################################
### Deploy ADDS forest in cloud
############################################################################

if ($Mode -eq "ADDS" -Or $Mode -eq "Prepare") {
    # Deploy AD tier in azure

    # Creating ADDS resource group
    Write-Host "Creating ADDS resource group..."
    $addsResourceGroup = New-AzureRmResourceGroup -Name $addsResourceGroupName -Location $Location

    # "Deploying ADDS servers..."
    Write-Host "Deploying ADDS servers..."
    New-AzureRmResourceGroupDeployment -Name "operational-adds-deployment" `
		-ResourceGroupName $addsResourceGroup.ResourceGroupName  -TemplateUri $virtualMachineTemplate.AbsoluteUri `
		-TemplateParameterFile $azureAddsVirtualMachinesParametersFile

    # Remove the Azure DNS entry since the forest will create a DNS forwarding entry.
    Write-Host "Updating virtual network DNS servers..."
    New-AzureRmResourceGroupDeployment -Name "operational-azure-dns-vnet-deployment" `
        -ResourceGroupName $addsResourceGroup.ResourceGroupName -TemplateUri $virtualNetworkTemplate.AbsoluteUri `
        -TemplateParameterFile $azureVirtualNetworkDnsParametersFile

    Write-Host "Creating ADDS forest..."
    New-AzureRmResourceGroupDeployment -Name "operational-azure-adds-forest-deployment" `
        -ResourceGroupName $addsResourceGroup.ResourceGroupName `
        -TemplateUri $virtualMachineExtensionsTemplate.AbsoluteUri -TemplateParameterFile $azureCreateAddsForestExtensionParametersFile

    Write-Host "Creating ADDS domain controller..."
    New-AzureRmResourceGroupDeployment -Name "operational-azure-adds-dc-deployment" `
        -ResourceGroupName $addsResourceGroup.ResourceGroupName `
        -TemplateUri $virtualMachineExtensionsTemplate.AbsoluteUri -TemplateParameterFile $azureAddAddsDomainControllerExtensionParametersFile

}


###########################################################################
## Deploy operational tier workloads loadbalancers & VMs
###########################################################################

if ($Mode -eq "Workload" -Or $Mode -eq "Prepare") {

    Write-Host "Creating workload resource group..."
    $workloadResourceGroup = New-AzureRmResourceGroup -Name $workloadResourceGroupName -Location $Location

	# Deploy management vnet network infrastructure
    Write-Host "Deploying management jumpbox..."
    New-AzureRmResourceGroupDeployment -Name "azure-mgmt-rg-deployment" -ResourceGroupName $workloadResourceGroup.ResourceGroupName `
        -TemplateUri $virtualMachineTemplate.AbsoluteUri -TemplateParameterFile $mgmtVMJumpboxParametersFile

	#Deploy workload tiers
    Write-Host "Deploying web load balancer..."
    New-AzureRmResourceGroupDeployment -Name "operational-web-deployment"  `
		-ResourceGroupName $workloadResourceGroup.ResourceGroupName `
        -TemplateUri $loadBalancerTemplate.AbsoluteUri -TemplateParameterFile $webLoadBalancerParametersFile

    Write-Host "Deploying biz load balancer..."
    New-AzureRmResourceGroupDeployment -Name "operational-biz-deployment" -ResourceGroupName $workloadResourceGroup.ResourceGroupName `
        -TemplateUri $loadBalancerTemplate.AbsoluteUri -TemplateParameterFile $bizLoadBalancerParametersFile

    Write-Host "Deploying data load balancer..."
    New-AzureRmResourceGroupDeployment -Name "operational-data-deployment" -ResourceGroupName $workloadResourceGroup.ResourceGroupName `
        -TemplateUri $loadBalancerTemplate.AbsoluteUri -TemplateParameterFile $dataLoadBalancerParametersFile

 }

##############################################################################
##### Domain join VMs
##############################################################################

if ($Mode -eq "Post" -Or $Mode -eq "Prepare") {


    #Get Operational Resource groups
	Write-Host "Get Operational resource group..."
    $workloadResourceGroup = Get-AzureRmResourceGroup -Name $workloadResourceGroupName

	#Domain join operational machines
	Write-Host "Joining Operational Vms to domain..."
    New-AzureRmResourceGroupDeployment -Name "vm-join-domain-deployment" -ResourceGroupName $workloadResourceGroup.ResourceGroupName `
        -TemplateUri $virtualMachineExtensionsTemplate.AbsoluteUri -TemplateParameterFile $azurenVmDomainJoinExtensionParametersFile

	#Enable windows authentication
    Write-Host "Enable Windows Auth for Operational Vms..."
    New-AzureRmResourceGroupDeployment -Name "vm-enable-windows-auth"  -ResourceGroupName $workloadResourceGroup.ResourceGroupName `
        -TemplateUri $virtualMachineExtensionsTemplate.AbsoluteUri -TemplateParameterFile $azureVmEnableWindowsAuthExtensionParametersFile
    
    
 }







