#!/bin/bash

# load environment variables
set -a && source .env && set +a

# Required variables
required_vars=(
    "resource_group"
    "location"
    "customLocationName"
    "schemaRegistryResourceGroup"
    "schemaRegistryName"
    "aioInstanceName"
    "adxClusterUri"
    "adxDatabaseName"
    "adxTableName"
    "mqttTopic"
)

# Set the current directory to where the script lives.
cd "$(dirname "$0")"

# Function to check if all required arguments have been set
check_required_arguments() {
    # Array to store the names of the missing arguments
    local missing_arguments=()

    # Loop through the array of required argument names
    for arg_name in "${required_vars[@]}"; do
        # Check if the argument value is empty
        if [[ -z "${!arg_name}" ]]; then
            # Add the name of the missing argument to the array
            missing_arguments+=("${arg_name}")
        fi
    done

    # Check if any required argument is missing
    if [[ ${#missing_arguments[@]} -gt 0 ]]; then
        echo -e "\nError: Missing required arguments:"
        printf '  %s\n' "${missing_arguments[@]}"
        [ ! \( \( $# == 1 \) -a \( "$1" == "-c" \) \) ] && echo "  Either provide a .env file or all the arguments, but not both at the same time."
        [ ! \( $# == 22 \) ] && echo "  All arguments must be provided."
        echo ""
        exit 1
    fi
}


# Check if all required arguments have been set
check_required_arguments

#
# Create/Get a resource group.
#
rg_query=$(az group list --query "[?name=='$resource_group']")
if [ "$rg_query" == "[]" ]; then
   echo -e "\nCreating Resource group '$resource_group'"
   az group create --name ${resource_group} --location ${location}
else
   echo "Resource group $resource_group already exists."
   #RG_ID=$(az group show --name $RESOURCE_GROUP --query id -o tsv)
fi

#
# Create lab
#
az deployment group create \
      --name adx-dataflow \
      --resource-group $resource_group \
      --template-file ./adx-dataflow.bicep \
      --parameters customLocationName=$customLocationName \
      --parameters schemaRegistryResourceGroup=$schemaRegistryResourceGroup \
      --parameters schemaRegistryName=$schemaRegistryName \
      --parameters aioInstanceName=$aioInstanceName \
      --parameters mqttTopic=$mqttTopic \
      --parameters adxDatabaseName=$adxDatabaseName \
      --parameters adxTableName=$adxTableName \
      --parameters adxClusterUri="${adxClusterUri}"

exit 0
