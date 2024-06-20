#!/bin/bash

# Script to release a CIDR block from an AWS IPv4 pool

# Input parameters
AWS_REGION=$1
POOL_ID=$2
CIDR_VALUE=$3
ACCT_ID=$4  # Added parameter for AWS account name


# Check if all parameters are provided
if [[ -z "$AWS_REGION" || -z "$POOL_ID" || -z "$CIDR_VALUE" || -z "$AWS_ACCOUNT_NAME" ]]; then
    echo "Usage: $0 <region> <ipv4-pool-id> <cidr-value> <aws-account-name>"
fi

# Calculates the ip addresses in the CIDR block and stores them in array
cidr_ip_calculator() {
  CIDR=${CIDR_VALUE}

  # Function to convert an IP address to a 32-bit integer
  ip_to_int() {
      local IFS=.
      local -a octets=($1)
      echo $(( (octets[0] << 24) + (octets[1] << 16) + (octets[2] << 8) + octets[3] ))
  }

  # Function to convert a 32-bit integer to an IP address
  int_to_ip() {
      local ip=$1
      echo "$(( (ip >> 24) & 0xFF )).$(( (ip >> 16) & 0xFF )).$(( (ip >> 8) & 0xFF )).$(( ip & 0xFF ))"
  }

  # Extract the IP address and the subnet mask
  IFS=/ read -r ip mask <<< "$CIDR"

  # Convert IP address to a 32-bit integer
  ip_int=$(ip_to_int $ip)

  # Calculate the number of IP addresses in the CIDR block
  num_ips=$(( 2 ** (32 - mask) ))

  # Calculate the network address
  network_int=$(( ip_int & ~(num_ips - 1) ))

  # Calculate the broadcast address
  broadcast_int=$(( network_int + num_ips - 1 ))

  # Initialize an array to store the IP addresses
  ip_array=()

  # Generate all IP addresses in the range and store them in the array
  for ((i = network_int; i <= broadcast_int; i++)); do
      ip_array+=( "$(int_to_ip $i)" )
  done
}

generate_ip_range_array() {
    first_ip=$First_ip
    last_ip=$Last_ip

    if [ -z "$First_ip" ] && [ -z "$Last_ip" ]; then
      echo "No Addresses Found"
      return 1
    fi


    # Extract the octets of the first and last IP addresses
    IFS='.' read -r -a first_ip_octets <<< "$first_ip"
    IFS='.' read -r -a last_ip_octets <<< "$last_ip"

    # Convert the octets to integers
    first_octet=${first_ip_octets[0]}
    second_octet=${first_ip_octets[1]}
    third_octet=${first_ip_octets[2]}
    fourth_octet=${first_ip_octets[3]}

    last_octet=${last_ip_octets[3]}

    # Initialize an array to store the IP addresses
    ip_pool_array=()

    # Loop through the IP range and generate each IP address
    for (( i = $fourth_octet; i <= $last_octet; i++ )); do
        ip_pool_array+=("$first_octet.$second_octet.$third_octet.$i")
    done

    # Append the IP addresses to the global array
    all_ip_addresses+=("${ip_pool_array[@]}")

    echo "IP addresses are ${ip_pool_array[*]}"
}

# Function to find the pool ID containing the CIDR
find_pool_id() {
  echo "Finding CIDR ${CIDR_VALUE} in the IPv4 pool"
  describe_pools_output=$(aws ec2 describe-public-ipv4-pools --region "$AWS_REGION")
  cidr_ip_calculator
  echo "IP addresses in CIDR are ${ip_array[*]}"

  all_ip_addresses=()
  Pool_ids=$(echo "$describe_pools_output" | jq -r '.PublicIpv4Pools[].PoolId')
  echo ${Pool_ids[*]}
  for pool_id in ${Pool_ids[@]}
  do
    echo "Addresses in $pool_id Pool Id"
    First_ip=$(echo "$describe_pools_output" | jq -r --arg pool_id "$pool_id" '.PublicIpv4Pools[] | select(.PoolId == $pool_id) | .PoolAddressRanges[].FirstAddress')
    Last_ip=$(echo "$describe_pools_output" | jq -r --arg pool_id "$pool_id" '.PublicIpv4Pools[] | select(.PoolId == $pool_id) | .PoolAddressRanges[].LastAddress')
    generate_ip_range_array
  done

  # the 1st ip address
  ip=${CIDR_VALUE::-3}
  echo "IP address to be checked $ip"
  # Initialize the counter
  counter=0

  # Iterate over all_ip_addresses
  for ips in "${all_ip_addresses[@]}"; do
    # Split ips into an array
    echo $ips
    IFS=' ' read -r -a ip_array <<< "$ips"

    # Iterate over each IP in ip_array
    for IP in "${ips[@]}"; do
      if [[ "$IP" == "$ip" ]]; then
        echo "$ip Found"
        break 2
      fi
    done

    # Increment the counter
    counter=$((counter + 1))
  done

  # Get the corresponding pool_id
  IFS=' ' read -r -a Pool_ids <<< "$Pool_ids"
  POOL_ID=${Pool_ids[counter]}
  echo "Select pool id is $POOL_ID"

  # POOL_ID=$(echo "$describe_pools_output" | jq -r --arg ipfst "${ip_array[0]}" '.PublicIpv4Pools[] | select(.PoolAddressRanges[]? | (.FirstAddress == $ipfst)) | .PoolId')
  
  if [ -z "$POOL_ID" ]; then
    echo "Error: CIDR ${CIDR_VALUE} not found in any IPv4 pool"
    exit 1
  fi
  
  echo "Found CIDR ${CIDR_VALUE} in pool ${POOL_ID}"
  echo "$POOL_ID"
}

# Function to deprovision the CIDR block
deprovision_cidr() {
    echo "Deprovisioning CIDR "${CIDR_VALUE::-3}/32" from pool $POOL_ID in region $AWS_REGION for account $AWS_ACCOUNT_NAME..." 
    local output=$(aws ec2 deprovision-public-ipv4-pool-cidr --region "$AWS_REGION" --pool-id "$POOL_ID" --cidr "${CIDR_VALUE::-3}/32" 2>&1)
    echo $output
    local status=$?

    if [ $status -ne 0 ]; then
    echo "Failed to deprovision CIDR: $output"
    return $status
    else
    echo "Successfully deprovisioned CIDR: $CIDR_VALUE"
    fi
}

# Execute the function
find_pool_id
deprovision_cidr
