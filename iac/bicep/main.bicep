targetScope = 'subscription'

// Parameters
@description('Resource group where Microsoft Fabric capacity will be deployed. Resource group will be created if it doesnt exist')
param dprg string = 'cdp'

@description('Microsoft Fabric Resource group location')
param rglocation string = 'australiasoutheast'

@description('Cost Centre tag that will be applied to all resources in this deployment')
param cost_centre_tag string = 'cdp'

@description('System Owner tag that will be applied to all resources in this deployment')
param owner_tag string = 'Curt Martin'


@description('Subject Matter EXpert (SME) tag that will be applied to all resources in this deployment')
param sme_tag string ='Curt Martin'


@description('Timestamp that will be appended to the deployment name')
var deployment_suffix = uniqueString(subscription().id, rglocation)

@description('Flag to indicate whether to create a new Purview resource with this data platform deployment')
param create_purview bool = true

@description('Flag to indicate whether to enable integration of data platform resources with either an existing or new Purview resource')
param enable_purview bool = true

@description('Resource group where Purview will be deployed. Resource group will be created if it doesnt exist')
param purviewrg string = 'purviewcdp'

@description('Location of Purview resource. This may not be same as the Fabric resource group location')

param purview_location string= 'australiaeast'

@description('Resource Name of new or existing Purview Account. Must be globally unique. Specify a resource name if either create_purview=true or enable_purview=true')
param purview_name string = 'curtlymartin-cdp-purview'

@description('Flag to indicate whether auditing of data platform resources should be enabled')
param enable_audit bool = true

@description('Resource group where audit resources will be deployed if enabled. Resource group will be created if it doesnt exist')
param auditrg string = 'auditcdp'



// Variables
var fabric_deployment_name = 'fabric_dataplatform_deployment_${deployment_suffix}'
var purview_deployment_name = 'purview_deployment_${deployment_suffix}'
var keyvault_deployment_name = 'keyvault_deployment_${deployment_suffix}'
var audit_deployment_name = 'audit_deployment_${deployment_suffix}'
var controldb_deployment_name = 'controldb_deployment_${deployment_suffix}'


// Create data platform resource group
resource fabric_rg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: dprg
  location: rglocation
  tags: {
    CostCentre: cost_centre_tag
    Owner: owner_tag
    SME: sme_tag
  }
}

// Create Purview resource group
resource purview_rg 'Microsoft.Resources/resourceGroups@2024-03-01' = if (create_purview) {
  name: purviewrg
  location: purview_location
  tags: {
    CostCentre: cost_centre_tag
    Owner: owner_tag
    SME: sme_tag
  }
}

// Create audit resource group
resource audit_rg 'Microsoft.Resources/resourceGroups@2024-03-01' = if (enable_audit) {
  name: auditrg
  location: rglocation
  tags: {
    CostCentre: cost_centre_tag
    Owner: owner_tag
    SME: sme_tag
  }
}

// Deploy Purview using module
module purview './modules/purview.bicep' = if (create_purview || enable_purview) {
  name: purview_deployment_name
  scope: purview_rg
  params: {
    create_purview: create_purview
    enable_purview: enable_purview
    purviewrg: purviewrg
    purview_name: purview_name
    location: purview_location
    cost_centre_tag: cost_centre_tag
    owner_tag: owner_tag
    sme_tag: sme_tag
  }
}

// Deploy Key Vault with default access policies using module
module kv './modules/keyvault.bicep' = {
  name: keyvault_deployment_name
  scope: fabric_rg
  params: {
    location: fabric_rg.location
    keyvault_name: 'cdp-kv01'
    cost_centre_tag: cost_centre_tag
    owner_tag: owner_tag
    sme_tag: sme_tag
    purview_account_name: (create_purview || enable_purview) ? purview.outputs.purview_account_name : ''
    purviewrg: (create_purview || enable_purview) ? purviewrg : ''
    enable_purview: enable_purview
  }
}

resource kv_ref 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: kv.outputs.keyvault_name
  scope: fabric_rg
}

// Enable auditing for data platform resources
module audit_integration './modules/audit.bicep' = if (enable_audit) {
  name: audit_deployment_name
  scope: audit_rg
  params: {
    location: audit_rg.location
    cost_centre_tag: cost_centre_tag
    owner_tag: owner_tag
    sme_tag: sme_tag
    audit_storage_name:'cdpauditstorage01'
    audit_storage_sku: 'Standard_LRS'
    audit_loganalytics_name: 'cdp-loganalytics01'
  }
}

// Deploy Microsoft Fabric Capacity
module fabric_capacity './modules/fabric-capacity.bicep' = {
  name: fabric_deployment_name
  scope: fabric_rg
  params: {
    fabric_name: 'cdpfabric01'
    location: fabric_rg.location
    cost_centre_tag: cost_centre_tag
    owner_tag: owner_tag
    sme_tag: sme_tag
    adminUsers: kv_ref.getSecret('fabric-capacity-admin-username')
    skuName: 'F2'
  }
}

// Deploy SQL control DB
module controldb './modules/sqldb.bicep' = {
  name: controldb_deployment_name
  scope: fabric_rg
  params: {
    sqlserver_name: 'cdp-sql01'
    database_name: 'cdpcontrolDB'
    location: fabric_rg.location
    cost_centre_tag: cost_centre_tag
    owner_tag: owner_tag
    sme_tag: sme_tag
    ad_admin_username: kv_ref.getSecret('sqlserver-ad-admin-username')
    ad_admin_sid: kv_ref.getSecret('sqlserver-ad-admin-sid')
    auto_pause_duration: 60
    database_sku_name: 'GP_S_Gen5_1'
    enable_purview: enable_purview
    purview_resource: (create_purview || enable_purview) ? purview.outputs.purview_resource : {}
    enable_audit: false
    audit_storage_name: enable_audit ? audit_integration.outputs.audit_storage_uniquename : ''
    auditrg: enable_audit ? audit_rg.name : ''
  }
}
