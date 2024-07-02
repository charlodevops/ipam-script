#!/bin/bash

# Script to Request or Release a CIDR block from an AWS IPv4 pool

AWS_REGION=$1
POOL_ID=$2
CIDR_VALUE=$3  # e.g., /32, /31, /30, /28
SHARED_IPAM_POOL_ID=$4
ACCT_ID=$5
ACTION=$6  # 'allocate' or 'release'

# Function to check for existing IPv4 pool
check_pool() {
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
      pool_id=$(echo $create_output | jq -r '.PoolId')
      
      if [ -z "$pool_id" ]; then
        echo "Failed to retrieve the new pool ID."
        exit 1
      fi
    else
      echo "Failed to create IPv4 pool."
      exit 1
    fi
  fi
}

# Function to retrieve shared IPAM pool ID
get_shared_ipam_pool_id() {
  echo "Retrieving the shared IPAM pool ID..."
  shared_ipam_pool_id=$(aws ec2 describe-ipam-pools --region $AWS_REGION --query "IpamPools[?contains(Description, '$SHARED_IPAM_POOL_ID')].IpamPoolId" --output text)

  if [ -z "$shared_ipam_pool_id" ] || [ "$shared_ipam_pool_id" == "None" ]; then
    echo "Failed to find the shared IPAM pool with name ${SHARED_IPAM_POOL_ID}."
    exit 1
  fi
}

# Function to allocate CIDR block
allocate_cidr() {
  netmask_length=$(echo ${CIDR_VALUE} | cut -d\/ -f2)

  allocation_output=$(aws ec2 provision-public-ipv4-pool-cidr --region $AWS_REGION --ipam-pool-id $shared_ipam_pool_id --pool-id $pool_id --netmask-length ${netmask_length})

  if [ $? -eq 0 ]; then
    echo "Successfully allocated ${CIDR_VALUE} CIDR into the IPv4 pool."
    echo $allocation_output
  else
    echo $allocation_output
    echo "Failed to allocate ${CIDR_VALUE} CIDR into the IPv4 pool."
    exit 1
  fi
}

# Function to release CIDR block
release_cidr() {
  echo "Releasing ${CIDR_VALUE} CIDR from the IPv4 pool..."

  release_output=$(aws ec2 deprovision-public-ipv4-pool-cidr --region $AWS_REGION --pool-id $pool_id --cidr ${CIDR_VALUE})

  if [ $? -eq 0 ]; then
    echo "Successfully released ${CIDR_VALUE} CIDR from the IPv4 pool."
    echo $release_output
  else
    echo $release_output
    echo "Failed to release ${CIDR_VALUE} CIDR from the IPv4 pool."
    exit 1
  fi
}

# Main script execution
check_pool
get_shared_ipam_pool_id

if [ "$ACTION" == "allocate" ]; then
  allocate_cidr
elif [ "$ACTION" == "release" ]; then
  release_cidr
else
  echo "Invalid action specified. Use 'allocate' or 'release'."
  exit 1
fi
