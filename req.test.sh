#!/bin/bash

AWS_REGION="us-west-2" #not to be harded
POOL_NAME="fico-public-ip-local-ipv4-pool"
SHARED_IPAM_POOL_NAME="fico_shared_public_regional_us_west_2"

ASSUME_ROLE="arn:aws:iam::${ACCT_ID}:role/GTS-AWSEngineering"
ROLE_SESSION_NAME="terraform"
TMP_FILE="/tmp/${ACCT_ID}.credentials"

aws sts assume-role --output json --role-arn ${ASSUME_ROLE} --role-session-name ${ROLE_SESSION_NAME} > ${TMP_FILE}

ACCESS_KEY=$(cat ${TMP_FILE} | jq -r ".Credentials.AccessKeyId")
SECRET_KEY=$(cat ${TMP_FILE} | jq -r ".Credentials.SecretAccessKey")
SESSION_TOKEN=$(cat ${TMP_FILE} | jq -r ".Credentials.SessionToken")
EXPIRATION=$(cat ${TMP_FILE} | jq -r ".Credentials.Expiration")

#Check if a public IPv4 pool with the specified name already exists
echo "Checking for existing IPv4 pools with the name ${POOL_NAME} in region ${AWS_REGION}..."
pool_id=$(aws ec2 describe-public-ipv4-pools --region $AWS_REGION --query "PublicIpv4Pools[?contains(Tags[?Key=='Name'].Value, '$POOL_NAME')].PoolId" --output text)

if [ -n "$pool_id" ] && [ "$pool_id" != "None" ]; then
  echo "IPv4 pool already exists with ID: $pool_id"
else
  # If no pool exists, create a new IPv4 pool
  echo "No existing IPv4 pool found with the name ${POOL_NAME}. Creating a new pool..."
  create_output=$(aws ec2 create-public-ipv4-pool --region $AWS_REGION --tag-specifications "ResourceType=ipv4pool-ec2,Tags=[{Key=Name,Value=${POOL_NAME}}]")
  
  if [ $? -eq 0 ]; then
    echo "Successfully created IPv4 pool:"
    echo $create_output

    # Extract newly created pool ID
    pool_id=$(echo $create_output | jq -r '.PublicIpv4PoolId')
    
    if [ -z "$pool_id" ]; then
      echo "Failed to retrieve the new pool ID."
      exit 1
    fi
  else
    echo "Failed to create IPv4 pool."
    exit 1
  fi
fi

#Get the pool ID of the shared regional IPAM pool
echo "Retrieving the shared IPAM pool ID..."
shared_ipam_pool_id=$(aws ec2 describe-ipam-pools --region $AWS_REGION --query "IpamPools[?contains(Description, '$SHARED_IPAM_POOL_NAME')].IpamPoolId" --output text)

if [ -z "$shared_ipam_pool_id" ] || [ "$shared_ipam_pool_id" == "None" ]; then
  echo "Failed to find the shared IPAM pool with name ${SHARED_IPAM_POOL_NAME}."
  exit 1
fi

#Allocate a /32 CIDR into the IPv4 pool from the shared regional IPAM pool
echo "Allocating /32 CIDR into the IPv4 pool from shared IPAM pool..."
allocation_output=$(aws ec2 provision-public-ipv4-pool-cidr --region $AWS_REGION--ipam-pool-id $shared_ipam_pool_id --pool-id $pool_id --netmask-length 32)

if [ $? -eq 0 ]; then
  echo "Successfully allocated /32 CIDR into the IPv4 pool."
  echo $allocation_output
else
  echo "Failed to allocate /32 CIDR into the IPv4 pool."
  exit 1
fi
rm $TMP_FILE
