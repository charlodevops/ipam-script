The error message indicates that the aws ec2 deprovision-public-ipv4-pool-cidr command only accepts a /32 netmask for the CIDR parameter. This means you can only deprovision one IP address at a time, not a range of addresses.

If you have a range of IPs you need to deprovision, you'll need to deprovision each IP individually by specifying them with a /32 netmask.

Input Validation: Ensures that the required parameters (region, pool-id, cidr-block) are provided.
CIDR to IP Conversion: The cidr_to_ips function calculates all individual IP addresses within the provided CIDR block.
Deprovision Each IP: The script loops through each IP in the CIDR block and deprovisions it using the /32 netmask.

This will deprovision each IP address within the 165.109.232.80/28 CIDR block individually.


#!/bin/bash

# Input parameters
REGION=$1
POOL_ID=$2
CIDR_BLOCK=$3

# Validate inputs
if [[ -z "$REGION" || -z "$POOL_ID" || -z "$CIDR_BLOCK" ]]; then
    echo "Usage: $0 <region> <ipv4-pool-id> <cidr-block>"
    exit 1
fi

# Function to calculate all IP addresses in a CIDR block
function cidr_to_ips {
    local cidr=$1
    local base_ip=$(echo $cidr | cut -d/ -f1)
    local prefix=$(echo $cidr | cut -d/ -f2)
    local ip_range=$(( 2 ** (32 - $prefix) ))
    local ip_dec=$(printf "%d" $(echo $base_ip | awk -F. '{print ($1 * 256 ** 3) + ($2 * 256 ** 2) + ($3 * 256) + $4}'))

    for (( i=0; i<$ip_range; i++ )); do
        ip=$(( $ip_dec + $i ))
        printf "%d.%d.%d.%d\n" $(( ($ip >> 24) & 255 )) $(( ($ip >> 16) & 255 )) $(( ($ip >> 8) & 255 )) $(( $ip & 255 ))
    done
}

# Deprovision each IP in the CIDR block
for ip in $(cidr_to_ips $CIDR_BLOCK); do
    echo "Deprovisioning CIDR $ip/32 from pool $POOL_ID in region $REGION..."
    aws ec2 deprovision-public-ipv4-pool-cidr --region $REGION --pool-id $POOL_ID --cidr $ip/32
    if [ $? -eq 0 ]; then
        echo "Successfully deprovisioned CIDR: $ip/32"
    else
        echo "Failed to deprovision CIDR: $ip/32"
    fi
done
