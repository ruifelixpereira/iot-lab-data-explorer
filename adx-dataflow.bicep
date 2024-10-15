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

// Parameters
param customLocationName string = 'aio-cl'
param defaultDataflowEndpointName string = 'default'
param defaultDataflowProfileName string = 'default'
param schemaRegistryName string = 'aiosreg'
param aioInstanceName string = 'aio-ops-instance'

// Source MQTT topic
param mqttTopic string = 'thermostats/temperature'

// Target ADX
param adxClusterUri string = 'https://iot-ts.westus.kusto.windows.net'
param adxDatabaseName string = 'iot'
param adxTableName string = 'SensorData'

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

resource schemaRegistry 'Microsoft.DeviceRegistry/schemaRegistries@2024-09-01-preview' existing = {
  name: schemaRegistryName
}

resource opcSchema 'Microsoft.DeviceRegistry/schemaRegistries/schemas@2024-09-01-preview' = {
  parent: schemaRegistry
  name: opcuaSchemaName
  properties: {
    displayName: 'Sensor Temperature Custom Delta Schema'
    description: 'This is a custom delta Schema'
    format: 'Delta/1.0'
    schemaType: 'MessageSchema'
  }
}

resource opcuaSchemaInstance 'Microsoft.DeviceRegistry/schemaRegistries/schemas/schemaVersions@2024-09-01-preview' = {
  parent: opcSchema
  name: opcuaSchemaVer
  properties: {
    description: 'Schema version'
    schemaContent: opcuaSchemaContent
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
