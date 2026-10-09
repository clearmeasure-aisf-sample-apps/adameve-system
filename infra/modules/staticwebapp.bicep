// adameve's own version of this module (fleet.ownedTemplates of its registry file, Jeffrey's decision of 2026-10-09):
// for this system, hosting "staticwebapp" means "a static site". The kit's module creates a Static Web App on the Free
// plan; the subscription holds at most 10 of them and all 10 are in use, so an eleventh fails the template's validation.
//
// One storage account per static deployable of system.json and environment (the health dashboard: a site of static
// files, with no server and no database), whose static website serves the files. Standard_LRS, about a cent a month
// for a site of this size. No key opens it: shared keys are off, and Octopus writes the release's files as the tier's
// deploy identity (scripts/deploy-staticwebapp.ps1), which this module makes a writer of the account's blobs.
// The website itself is switched on by the first release: Azure Resource Manager has no property for it. Until then
// the site's address answers 404 (scripts/verify-environment.ps1 passes over a site that has had no release).
// What a storage website does not have, against a Static Web App: no edge locations (the files are served from the
// account's region), no compression on the way out, no custom response header and no CORS answer.
// main.bicep passes system.staticLocation as the location (centralus unless set); any region has storage accounts.
targetScope = 'resourceGroup'

param slug string
param environmentName string
param location string
param tags object
param deployables array
param versions object

// The identity Octopus deploys as in this tier, which the seed created in this resource group.
resource deployIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = {
  name: 'id-${slug}-deploy-${tags.tier}'
}

// A storage account's name is 3 to 24 lowercase letters and digits, and it is the first label of the site's address.
// It is spelled from the names alone, so that the runtime diagram of another environment can name it too
// (scripts/deploy-staticwebapp.ps1, Get-StaticSiteName).
resource accounts 'Microsoft.Storage/storageAccounts@2023-05-01' = [
  for d in deployables: {
    name: take('st${slug}${environmentName}${replace(d.name, '-', '')}', 24)
    location: location
    tags: union(tags, { deployable: d.name })
    sku: {
      name: 'Standard_LRS'
    }
    kind: 'StorageV2'
    properties: {
      accessTier: 'Hot'
      allowBlobPublicAccess: false
      allowSharedKeyAccess: false
      minimumTlsVersion: 'TLS1_2'
      supportsHttpsTrafficOnly: true
    }
  }
]

// Storage Blob Data Contributor on the account alone: the deploy identity writes the site's files with no key.
resource writers 'Microsoft.Authorization/roleAssignments@2022-04-01' = [
  for (d, i) in deployables: {
    scope: accounts[i]
    name: guid(accounts[i].id, deployIdentity.id, 'blob-data-contributor')
    properties: {
      principalId: deployIdentity.properties.principalId
      principalType: 'ServicePrincipal'
      roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
      description: 'id-${slug}-deploy-${tags.tier}: Octopus writes the files of ${d.name} in ${environmentName}'
    }
  }
]

// The shape of the kit's module, so that every script that reads the stack's output finds the site as before:
// "staticSite" is the name of the storage account, and "url" its website address without the trailing slash Azure
// reports (the scripts add paths to it). The health path is / before and after the first release; before it, / answers
// 404.
output deployables array = [
  for (d, i) in deployables: {
    name: d.name
    hosting: 'staticwebapp'
    staticSite: accounts[i].name
    url: take(accounts[i].properties.primaryEndpoints.web, length(accounts[i].properties.primaryEndpoints.web) - 1)
    healthPath: '/'
    version: versions[?d.name] ?? ''
  }
]
