@description('Managed Identity of the resource being granted permissions')
param principalId string

@description('Role Definition ID to assign')
param roleDefinitionId string

resource roleAssignment 'Microsoft.Authorization/roleAssignments@2020-04-01-preview' = {
  name: guid(principalId, roleDefinitionId)
  properties: {
    principalType: 'ServicePrincipal'
    principalId: principalId
    roleDefinitionId: roleDefinitionId
  }
}
