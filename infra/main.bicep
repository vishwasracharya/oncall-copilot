// On-Call Copilot - Phase 1 infrastructure
// Blob Storage -> Event Grid -> Service Bus -> Azure Functions -> PostgreSQL (pgvector) + Azure OpenAI

@description('Region. Must support Flex Consumption, PostgreSQL Burstable B1ms and the models below.')
param location string = resourceGroup().location

@description('Region for PostgreSQL only. Change it if your subscription gets SkuNotAvailable for B1ms.')
param pgLocation string = location

@description('Short lowercase name used in every resource name.')
@maxLength(8)
param prefix string = 'oncall'

@secure()
@description('PostgreSQL admin password (no spaces or quotes). Moves to Key Vault in Phase 4.')
param pgAdminPassword string

@description('Set true after the first successful deploy so the OpenAI account is only referenced, never rewritten.')
param openAiExists bool = false

param chatModel string = 'gpt-5.4-mini'
param chatModelVersion string = '2026-03-17'
param embeddingModel string = 'text-embedding-3-small'
param embeddingModelVersion string = '1'

var suffix = uniqueString(resourceGroup().id)
var tags = { project: 'oncall-copilot' }

// Built-in role IDs (same in every tenant)
var roles = {
  storageBlobDataOwner: 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b'
  serviceBusDataReceiver: '4f6d3b9b-027b-4f4c-9142-0e5a2a2247e0'
  openAiUser: '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd'
}

// ---------- Storage: runbooks land here ----------

resource storage 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: 'st${prefix}${suffix}'
  location: location
  tags: tags
  kind: 'StorageV2'
  sku: { name: 'Standard_LRS' }
  properties: {
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
  }
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: storage
  name: 'default'
}

resource runbooksContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blobService
  name: 'runbooks'
}

resource deploymentsContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blobService
  name: 'deployments' // Flex Consumption keeps the function's code package here
}

// ---------- Service Bus: buffer between "file uploaded" and "file processed" ----------

resource serviceBus 'Microsoft.ServiceBus/namespaces@2021-11-01' = {
  name: '${prefix}-sb-${suffix}'
  location: location
  tags: tags
  sku: { name: 'Basic', tier: 'Basic' } // Phase 2 needs topics -> Standard
}

resource ingestQueue 'Microsoft.ServiceBus/namespaces/queues@2021-11-01' = {
  parent: serviceBus
  name: 'ingest'
  properties: {
    maxDeliveryCount: 5 // after 5 failed attempts the message moves to the dead-letter queue
    lockDuration: 'PT5M'
    deadLetteringOnMessageExpiration: true
  }
}

// ---------- Event Grid: "a .md file was uploaded to runbooks/" -> Service Bus ----------

resource systemTopic 'Microsoft.EventGrid/systemTopics@2022-06-15' = {
  name: '${prefix}-egst-${suffix}'
  location: location
  tags: tags
  properties: {
    source: storage.id
    topicType: 'Microsoft.Storage.StorageAccounts'
  }
}

resource runbookUploaded 'Microsoft.EventGrid/systemTopics/eventSubscriptions@2022-06-15' = {
  parent: systemTopic
  name: 'runbook-uploaded'
  dependsOn: [runbooksContainer]
  properties: {
    destination: {
      endpointType: 'ServiceBusQueue'
      properties: { resourceId: ingestQueue.id }
    }
    filter: {
      includedEventTypes: ['Microsoft.Storage.BlobCreated']
      subjectBeginsWith: '/blobServices/default/containers/runbooks/'
      subjectEndsWith: '.md'
    }
    eventDeliverySchema: 'EventGridSchema'
    retryPolicy: {
      maxDeliveryAttempts: 10
      eventTimeToLiveInMinutes: 1440
    }
  }
}

// ---------- PostgreSQL + pgvector: the vector store ----------

resource postgres 'Microsoft.DBforPostgreSQL/flexibleServers@2024-08-01' = {
  name: '${prefix}-pg-${uniqueString(resourceGroup().id, pgLocation)}' // new region = new name (names are tied to a region)
  location: pgLocation
  tags: tags
  sku: { name: 'Standard_B1ms', tier: 'Burstable' }
  properties: {
    version: '16'
    administratorLogin: 'pgadmin'
    administratorLoginPassword: pgAdminPassword
    storage: { storageSizeGB: 32 }
    backup: { backupRetentionDays: 7, geoRedundantBackup: 'Disabled' }
    highAvailability: { mode: 'Disabled' }
  }
}

resource allowVector 'Microsoft.DBforPostgreSQL/flexibleServers/configurations@2024-08-01' = {
  parent: postgres
  name: 'azure.extensions' // extensions must be allow-listed before CREATE EXTENSION works
  properties: { value: 'VECTOR', source: 'user-defined' }
}

resource allowAzureServices 'Microsoft.DBforPostgreSQL/flexibleServers/firewallRules@2024-08-01' = {
  parent: postgres
  name: 'AllowAzureServices' // 0.0.0.0 = Azure services only. Private networking is out of scope for now.
  dependsOn: [allowVector] // server accepts one change at a time
  properties: { startIpAddress: '0.0.0.0', endIpAddress: '0.0.0.0' }
}

resource database 'Microsoft.DBforPostgreSQL/flexibleServers/databases@2024-08-01' = {
  parent: postgres
  name: 'copilot'
  dependsOn: [allowAzureServices]
}

// ---------- Azure OpenAI: embeddings + chat (keys disabled, identity only) ----------

var openAiName = '${prefix}-aoai-${suffix}'

resource newOpenai 'Microsoft.CognitiveServices/accounts@2024-10-01' = if (!openAiExists) {
  name: openAiName
  location: location
  tags: tags
  kind: 'OpenAI'
  sku: { name: 'S0' }
  properties: {
    customSubDomainName: openAiName
    disableLocalAuth: true
    publicNetworkAccess: 'Enabled'
  }
}

// Everything below uses this reference, so it works whether the account was just created or already existed.
resource openai 'Microsoft.CognitiveServices/accounts@2024-10-01' existing = {
  name: openAiName
}

resource embeddingDeployment 'Microsoft.CognitiveServices/accounts/deployments@2024-10-01' = {
  parent: openai
  name: embeddingModel
  dependsOn: [newOpenai]
  sku: { name: 'GlobalStandard', capacity: 50 } // capacity = thousands of tokens per minute
  properties: {
    model: { format: 'OpenAI', name: embeddingModel, version: embeddingModelVersion }
  }
}

resource chatDeployment 'Microsoft.CognitiveServices/accounts/deployments@2024-10-01' = {
  parent: openai
  name: chatModel
  dependsOn: [embeddingDeployment] // deployments on one account must be created one at a time
  sku: { name: 'GlobalStandard', capacity: 50 }
  properties: {
    model: { format: 'OpenAI', name: chatModel, version: chatModelVersion }
  }
}

// ---------- Monitoring ----------

resource logs 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: '${prefix}-logs-${suffix}'
  location: location
  tags: tags
  properties: {
    sku: { name: 'PerGB2018' }
    retentionInDays: 30
  }
}

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: '${prefix}-appi-${suffix}'
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logs.id
  }
}

// ---------- Azure Functions (Flex Consumption, Python) ----------

resource plan 'Microsoft.Web/serverfarms@2024-04-01' = {
  name: '${prefix}-plan-${suffix}'
  location: location
  tags: tags
  kind: 'functionapp'
  sku: { tier: 'FlexConsumption', name: 'FC1' }
  properties: { reserved: true }
}

resource functionApp 'Microsoft.Web/sites@2024-04-01' = {
  name: '${prefix}-func-${suffix}'
  location: location
  tags: tags
  kind: 'functionapp,linux'
  identity: { type: 'SystemAssigned' }
  properties: {
    serverFarmId: plan.id
    httpsOnly: true
    functionAppConfig: {
      deployment: {
        storage: {
          type: 'blobContainer'
          value: '${storage.properties.primaryEndpoints.blob}${deploymentsContainer.name}'
          authentication: { type: 'SystemAssignedIdentity' }
        }
      }
      scaleAndConcurrency: { maximumInstanceCount: 40, instanceMemoryMB: 2048 }
      runtime: { name: 'python', version: '3.12' }
    }
    siteConfig: {
      appSettings: [
        { name: 'AzureWebJobsStorage__accountName', value: storage.name }
        { name: 'APPLICATIONINSIGHTS_CONNECTION_STRING', value: appInsights.properties.ConnectionString }
        { name: 'ServiceBusConnection__fullyQualifiedNamespace', value: '${serviceBus.name}.servicebus.windows.net' }
        { name: 'AZURE_OPENAI_ENDPOINT', value: openai.properties.endpoint }
        { name: 'EMBEDDING_DEPLOYMENT', value: embeddingDeployment.name }
        { name: 'CHAT_DEPLOYMENT', value: chatDeployment.name }
        // Phase 1 shortcut: password sits in an app setting. Phase 4 moves it to Key Vault.
        {
          name: 'PG_CONN'
          value: 'host=${postgres.properties.fullyQualifiedDomainName} dbname=${database.name} user=pgadmin password=${pgAdminPassword} sslmode=require'
        }
      ]
    }
  }
}

// ---------- Permissions for the Function's managed identity ----------

resource funcCanUseStorage 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: storage
  name: guid(storage.id, functionApp.id, roles.storageBlobDataOwner)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.storageBlobDataOwner)
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource funcCanReadQueue 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: serviceBus
  name: guid(serviceBus.id, functionApp.id, roles.serviceBusDataReceiver)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.serviceBusDataReceiver)
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource funcCanUseOpenAi 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: openai
  name: guid(openai.id, functionApp.id, roles.openAiUser)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.openAiUser)
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

output functionAppName string = functionApp.name
output storageAccountName string = storage.name
output askUrl string = 'https://${functionApp.properties.defaultHostName}/api/ask'
