#!/bin/bash

echo "retrieving storage connection string"
AZURE_STORAGE_CONNECTION_STRING=$(az storage account show-connection-string --name $AZURE_STORAGE_ACCOUNT -g $RESOURCE_GROUP -o tsv)

echo "creating 'database' container"
az storage container create --connection-string $AZURE_STORAGE_CONNECTION_STRING --name database \
    -o tsv >> log.txt

echo "updloading bacpac"
az storage blob upload --connection-string $AZURE_STORAGE_CONNECTION_STRING --container-name database --name streaming.bacpac --file streaming.bacpac \
    -o tsv >> log.txt

echo "retrieving blob url"
BLOB_URL="$(az storage blob url --connection-string $AZURE_STORAGE_CONNECTION_STRING --container-name database --name streaming.bacpac -o tsv)"

echo "retrieving container sas"
EXPIRE_ON=$(date -u -d "30 minutes" '+%Y-%m-%dT%H:%MZ')
BLOB_SAS="?$(az storage container generate-sas --connection-string $AZURE_STORAGE_CONNECTION_STRING --name database --permissions lr --https-only --expiry $EXPIRE_ON -o tsv)"

echo "deploying azure sql"
echo ". server: $SQL_SERVER_NAME"
echo ". database: $SQL_DATABASE_NAME"

SERVER_EXIST=$( az sql server list -g $RESOURCE_GROUP -o tsv --query "[].name" | grep $SQL_SERVER_NAME)
if [ -z ${SERVER_EXIST+x} ]; then
    DB_EXISTS-$(az sql db list -g $RESOURCE_GROUP -s $SQL_SERVER_NAME -o tsv --query "[].name" | grep streaming)
    if [ -z ${DB_EXISTS+x} ]; then
        az sql db delete -g $RESOURCE_GROUP -s $SQL_SERVER_NAME -n $SQL_DATABASE_NAME
    fi
fi

az group deployment create \
    --name "$RESOURCE_GROUP-AzureSQL" \
    --resource-group "$RESOURCE_GROUP" \
    --template-file "arm/azure-sql.json" \
    --parameters \
        ServerName=$SQL_SERVER_NAME \
        DatabaseName=$SQL_DATABASE_NAME \
	    AdminLogin="serveradmin" \
	    AdminLoginPassword="Strong_Passw0rd!" \
        DacPacPath=$BLOB_URL \
        DacPacContainerSAS=$BLOB_SAS \
        SKU=$SQL_SKU \
	--verbose \
    -o tsv >> log.txt