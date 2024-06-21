#!/bin/bash
# Script to Request a CIDR block from an AWS IPv4 pool
# 1. Check to see if an IPv4 pool already exists in this account in this region.  If not, create one.
# 2. Provision a CIDR specify by the requestor for ex. /32 /30 /31 /28 /24 to the member account IPv4 pool from the shared regional IPAM pool that meets the size requested



AWS_REGION=$1
POOL_ID=$2
CIDR_VALUE=$3 .... for ex. /32  /31  /30  /28
SHARED_IPAM_POOL_ID=$4
ACCT_ID=$5

#AWS_REGION="us-west-2" #not to be harded
#POOL_ID="fico-public-ip-local-ipv4-pool"
#SHARED_IPAM_POOL_ID="fico_shared_public_regional_us_west_2"

#Check if a public IPv4 pool with the specified name already exists
echo "Checking for existing IPv4 pools with the name ${POOL_ID} in region ${AWS_REGION}..."
pool_id=$(aws ec2 describe-public-ipv4-pools --region $AWS_REGION --query "PublicIpv4Pools[?contains(Tags[?Key=='Name'].Value, '$POOL_ID')].PoolId" --output text)

if [ -n "$pool_id" ] && [ "$pool_id" != "None" ]; then
  echo "IPv4 pool already exists with ID: $pool_id"
else
  # If no pool exists, create a new IPv4 pool
  echo "No existing IPv4 pool found with the name ${POOL_ID}. Creating a new pool..."
  create_output=$(aws ec2 create-public-ipv4-pool --region $AWS_REGION --tag-specifications "ResourceType=ipv4pool-ec2,Tags=[{Key=Name,Value=${POOL_ID}}]")
  
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
shared_ipam_pool_id=$(aws ec2 describe-ipam-pools --region $AWS_REGION --query "IpamPools[?contains(Description, '$SHARED_IPAM_POOL_ID')].IpamPoolId" --output text)

if [ -z "$shared_ipam_pool_id" ] || [ "$shared_ipam_pool_id" == "None" ]; then
  echo "Failed to find the shared IPAM pool with name ${SHARED_IPAM_POOL_ID}."
  exit 1
fi

#Allocate provided CIDR into the IPv4 pool from the shared regional IPAM pool
echo "Allocating ${CIDR_VALUE} CIDR into the IPv4 pool from shared IPAM pool..."

netmask_length =`echo ${CIDR_VALUE}|cut -d\/ -f2`

allocation_output=$(aws ec2 provision-public-ipv4-pool-cidr --region $AWS_REGION--ipam-pool-id $shared_ipam_pool_id --pool-id $pool_id --netmask-length ${netmask_length})

if [ $? -eq 0 ]; then
  echo "Successfully allocated ${CIDR_VALUE} CIDR into the IPv4 pool."
  echo $allocation_output
else
  echo "Failed to allocate ${CIDR_VALUE} CIDR into the IPv4 pool."
  exit 1
fi

