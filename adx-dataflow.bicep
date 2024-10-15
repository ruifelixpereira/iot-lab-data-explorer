var opcuaSchemaContent = '''
{
  "$schema": "Delta/1.0",
  "type": "object",
  "properties": {
    "type": "struct",
    "fields": [
      { "name": "AssetId", "type": "string", "nullable": true, "metadata": {} },
      { "name": "Temperature", "type": "double", "nullable": true, "metadata": {} },
      { "name": "Timestamp", "type": "string", "nullable": true, "metadata": {} }
    ]
  }
}
'''

// Parameters AIO
param customLocationName string = 'aio-cl'
param defaultDataflowEndpointName string = 'default'
param defaultDataflowProfileName string = 'default'
param aioInstanceName string = 'aio-ops-instance'

// Source MQTT topic
param mqttTopic string = 'thermostats/temperature'

// Target ADX
param adxClusterUri string = 'https://iot-ts.westus.kusto.windows.net'
param adxDatabaseName string = 'iot'
param adxTableName string = 'SensorData'

// Schema Registry
param schemaRegistryResourceGroup string = 'iot-lab'
param schemaRegistryName string = 'aiosreg'

// Schema
param opcuaSchemaName string = 'sensor-data-delta'
param opcuaSchemaVer string = '1'


resource customLocation 'Microsoft.ExtendedLocation/customLocations@2021-08-31-preview' existing = {
  name: customLocationName
}

resource aioInstance 'Microsoft.IoTOperations/instances@2024-08-15-preview' existing = {
  name: aioInstanceName
}

resource defaultDataflowEndpoint 'Microsoft.IoTOperations/instances/dataflowEndpoints@2024-08-15-preview' existing = {
  parent: aioInstance
  name: defaultDataflowEndpointName
}

resource defaultDataflowProfile 'Microsoft.IoTOperations/instances/dataflowProfiles@2024-08-15-preview' existing = {
  parent: aioInstance
  name: defaultDataflowProfileName
}

// Schema
module schemaModule './modules/schema-registry.bicep' = {
  name: 'schemaDeploy'
  scope: resourceGroup(schemaRegistryResourceGroup)
  params: {
    schemaRegistryName: schemaRegistryName
    opcuaSchemaName: opcuaSchemaName
    opcuaSchemaVer: opcuaSchemaVer
    opcuaSchemaContent: opcuaSchemaContent
  }
}

// ADX Endpoint
resource adxEndpoint 'Microsoft.IoTOperations/instances/dataflowEndpoints@2024-08-15-preview' = {
  parent: aioInstance
  name: 'adx-ep'
  extendedLocation: {
    name: customLocation.id
    type: 'CustomLocation'
  }
  properties: {
    endpointType: 'DataExplorer'
    dataExplorerSettings: {
      authentication: {
        method: 'SystemAssignedManagedIdentity'
        systemAssignedManagedIdentitySettings: {}
      }
      host: adxClusterUri
      database: adxDatabaseName
      batching: {
        latencySeconds: 5
        maxMessages: 10000
      }
    }
  }
}

// ADX dataflow
resource dataflow_adx 'Microsoft.IoTOperations/instances/dataflowProfiles/dataflows@2024-08-15-preview' = {
  parent: defaultDataflowProfile
  name: 'adx-dataflow'
  extendedLocation: {
    name: customLocation.id
    type: 'CustomLocation'
  }
  properties: {
    mode: 'Enabled'
    operations: [
      {
        operationType: 'Source'
        sourceSettings: {
          endpointRef: defaultDataflowEndpoint.name
          dataSources: array(mqttTopic)
        }
      }
      {
        operationType: 'BuiltInTransformation'
        builtInTransformationSettings: {
          map: [
            {
              inputs: array('*')
              output: '*'
            }
          ]
          schemaRef: 'aio-sr://${opcuaSchemaName}:${opcuaSchemaVer}'
          serializationFormat: 'Parquet'
        }
      }
      {
        operationType: 'Destination'
        destinationSettings: {
          endpointRef: adxEndpoint.name
          dataDestination: adxTableName
        }
      }
    ]
  }
}
