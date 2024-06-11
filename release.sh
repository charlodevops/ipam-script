#!/bin/bash

# Script to release a CIDR block from an AWS IPv4 pool

# Input parameters
AWS_REGION=$1
POOL_ID=$2
CIDR_VALUE=$3
ACCT_ID=$4  # Added parameter for AWS account name


ASSUME_ROLE="arn:aws:iam::${ACCT_ID}:role/GTS-AWSEngineering"
ROLE_SESSION_NAME="terraform"
TMP_FILE="/tmp/${ACCT_ID}.credentials"

aws sts assume-role --output json --role-arn ${ASSUME_ROLE} --role-session-name ${ROLE_SESSION_NAME} > ${TMP_FILE}

ACCESS_KEY=$(cat ${TMP_FILE} | jq -r ".Credentials.AccessKeyId")
SECRET_KEY=$(cat ${TMP_FILE} | jq -r ".Credentials.SecretAccessKey")
SESSION_TOKEN=$(cat ${TMP_FILE} | jq -r ".Credentials.SessionToken")
EXPIRATION=$(cat ${TMP_FILE} | jq -r ".Credentials.Expiration")


# Check if all parameters are provided
if [[ -z "$AWS_REGION" || -z "$POOL_ID" || -z "$CIDR_VALUE" || -z "$AWS_ACCOUNT_NAME" ]]; then
    echo "Usage: $0 <region> <ipv4-pool-id> <cidr-value> <aws-account-name>"
    exit 1
fi

# Function to find the pool ID containing the CIDR
find_pool_id() {
  echo "Finding CIDR ${CIDR_VALUE} in the IPv4 pool"
  describe_pools_output=$(aws ec2 describe-public-ipv4-pools --region "$AWS_REGION")
  
  POOL_ID=$(echo "$describe_pools_output" | jq -r --arg CIDR "$CIDR_VALUE" '.PublicIpv4Pools[] | select(.AddressRanges[]?.Cidr == $CIDR_VALUE) | .PoolId')
  
  if [ -z "$POOL_ID" ]; then
    echo "Error: CIDR ${CIDR_VALUE} not found in any IPv4 pool"
    exit 1
  fi
  
  echo "Found CIDR ${CIDR_VALUE} in pool ${POOL_ID}"
  echo "$POOL_ID"
}

# Function to deprovision the CIDR block
deprovision_cidr() {
    echo "Deprovisioning CIDR $CIDR_VALUE from pool $POOL_ID in region $AWS_REGION for account $AWS_ACCOUNT_NAME..."
    local output=$(aws ec2 deprovision-public-ipv4-pool-cidr --region $AWS_REGION --pool-id $POOL_ID --cidr $CIDR_VALUE 2>&1)
    local status=$?

    if [ $status -ne 0 ]; then
        echo "Failed to deprovision CIDR: $output"
        return $status
    else
        echo "Successfully deprovisioned CIDR: $CIDR_VALUE"
    fi
}

# Execute the function
deprovision_cidr


