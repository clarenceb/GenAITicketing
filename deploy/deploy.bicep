@description('The location all resources will be deployed to')
param location string = resourceGroup().location

@description('A prefix to add to the start of all resource names. Note: A "unique" suffix will also be added')
param prefix string = 'ticket'

@description('Which variant of the logic app to deploy. "-withmove" will move the email once processed, "-nomove" will leave the email as-is')
@allowed([
  'emailtoazdo-withmove'
  'emailtoazdo-nomove'
  'apitoazdo'
])
param workflow string = 'emailtoazdo-nomove'

var logicAppType = {
  'emailtoazdo-withmove': {
    type: 'logicAppMulti'
  }
  'emailtoazdo-nomove': {
    type: 'logicAppMulti'
  }
  apitoazdo: {
    type: 'logicAppStd'
  }
}

@description('Tags to apply to all deployed resources')
param tags object = {}

var kind = 'StorageV2'
var skuName = 'Standard_LRS'
var skuTier = 'Standard'

var workflowDefinition = workflow == 'emailtoazdo-withmove' ? loadJsonContent('logicapps/emailtoazdo-withmove.json').definition : loadJsonContent('logicapps/emailtoazdo-nomove.json').definition

var strippedLocation = replace(toLower(location), ' ', '')
var uniqueNameFormat = '${prefix}-{0}-${uniqueString(resourceGroup().id, prefix)}'

var logicAppStdName = '${prefix}-logicappstd'
var appServicePlanName = '${prefix}-appserviceplan'
var storageName = '${prefix}${uniqueString(resourceGroup().id, prefix)}'

resource openai 'Microsoft.CognitiveServices/accounts@2023-05-01' = {
  name: format(uniqueNameFormat, 'openai')
  location: location
  kind: 'OpenAI'
  sku: {
    name: 'S0'
  }
  properties: {
    customSubDomainName: format(uniqueNameFormat, 'openai')
  }
  resource gpt35 'deployments@2023-05-01' = {
    name: 'gpt-35-turbo-16k'
    sku: {
      name: 'Standard'
      capacity: 20
    }
    properties: {
      model: {
        format: 'OpenAI'
        name: 'gpt-35-turbo-16k'
      }
      versionUpgradeOption: 'OnceNewDefaultVersionAvailable'
    }
  }
  tags: tags
}
resource openAIUserRoleDefinition 'Microsoft.Authorization/roleDefinitions@2018-01-01-preview' existing = {
  scope: subscription()
  name: '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd'
}
resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (logicAppType[workflow].type == 'logicAppMulti') {
  scope: openai
  name: guid(openai.id, logicapp.id)
  properties: {
    roleDefinitionId: openAIUserRoleDefinition.id
    principalId: logicapp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}
resource roleAssignmentStd 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (logicAppType[workflow].type == 'logicAppStd') {
  scope: openai
  name: guid(openai.id, logicAppStd.id)
  properties: {
    roleDefinitionId: openAIUserRoleDefinition.id
    principalId: logicAppStd.identity.principalId
    principalType: 'ServicePrincipal'
  }
}
resource azdoConnector 'Microsoft.Web/connections@2016-06-01' = {
  name: '${prefix}-azuredevops'
  location: location
  properties: {
    displayName: 'visualstudioteamservices'
    api: {
      id: subscriptionResourceId('Microsoft.Web/locations/managedApis', strippedLocation, 'visualstudioteamservices')
    }
  }
  tags: tags
}
resource office365Connector 'Microsoft.Web/connections@2016-06-01' = if (logicAppType[workflow].type == 'logicAppMulti') {
  name: '${prefix}-office365'
  location: location
  properties: {
    displayName: 'office365'
    api: {
      id: subscriptionResourceId('Microsoft.Web/locations/managedApis', strippedLocation, 'office365')
    }
  }
  tags: tags
}
resource logicapp 'Microsoft.Logic/workflows@2019-05-01' = if (logicAppType[workflow].type == 'logicAppMulti') {
  name: '${prefix}-logicapp'
  location: location
  properties: {
    definition: workflowDefinition
    parameters: {
      AzureOpenAIEndpoint: {
        value: openai.properties.endpoint
      }
      '$connections': {
        value: {
          office365: {
            connectionId: office365Connector.id
            connectionName: 'office365'
            id: subscriptionResourceId('Microsoft.Web/locations/managedApis', strippedLocation, 'office365')
          }
          visualstudioteamservices: {
            connectionId: azdoConnector.id
            connectionName: 'visualstudioteamservices'
            id: subscriptionResourceId('Microsoft.Web/locations/managedApis', strippedLocation, 'visualstudioteamservices')
          }
        }
      }
    }
  }
  identity: {
    type: 'SystemAssigned'
  }
  tags: tags
}
resource storage 'Microsoft.Storage/storageAccounts@2019-06-01' = if (logicAppType[workflow].type == 'logicAppStd') {
  sku: {
    name: skuName
    tier: skuTier
  }
  kind: kind
  name: substring('${storageName}', 0, 24)
  location: location
  tags: tags
}
resource appServicePlan 'Microsoft.Web/serverfarms@2018-02-01' = if (logicAppType[workflow].type == 'logicAppStd') {
  name: appServicePlanName
  location: location
  tags: tags
  sku: {
    name: 'WS1'
    tier: 'WorkflowStandard'
  }
  kind: 'windows'
}
resource logicAppStd 'Microsoft.Web/sites@2018-11-01' = if (logicAppType[workflow].type == 'logicAppStd') {
  name: logicAppStdName
  location: location
  kind: 'workflowapp,functionapp'
  identity: {
    type: 'SystemAssigned'
  }
  tags: tags
  properties: {
    serverFarmId: appServicePlan.id
    siteConfig: {
      netFrameworkVersion: 'v6.0'
      appSettings: [
        {
          name: 'APP_KIND'
          value: 'workflowApp'
        }
        {
          name: 'AzureFunctionsJobHost__extensionBundle__id'
          value: 'Microsoft.Azure.Functions.ExtensionBundle.Workflows'
        }
        {
          name: 'AzureFunctionsJobHost__extensionBundle__version'
          value: '[1.*, 2.0.0)'
        }
        {
          name: 'AzureWebJobsStorage'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageName};AccountKey=${listKeys('${resourceGroup().id}/providers/Microsoft.Storage/storageAccounts/${storageName}','2019-06-01').keys[0].value};EndpointSuffix=core.windows.net'
        }
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~4'
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: 'node'
        }
        {
          name: 'WEBSITE_CONTENTAZUREFILECONNECTIONSTRING'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageName};AccountKey=${listKeys('${resourceGroup().id}/providers/Microsoft.Storage/storageAccounts/${storageName}','2019-06-01').keys[0].value};EndpointSuffix=core.windows.net'
        }
        {
          name: 'WEBSITE_CONTENTSHARE'
          value: logicAppStdName
        }
        {
          name: 'WEBSITE_NODE_DEFAULT_VERSION'
          value: '~18'
        }
      ]
    }
    clientAffinityEnabled: false
  }
  dependsOn: [
    storage
  ]
}
