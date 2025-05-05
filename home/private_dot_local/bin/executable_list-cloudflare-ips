#!/usr/bin/env bash
#
# Prints out the latest Cloudflare IP list.
#
# Note: Third party Cloudflare workers can still access your site even if you 
# block traffic from this range.

readarray -t ips < <(curl -s https://www.cloudflare.com/ips-v4)
readarray -t -O"${#ips[@]}" ips < <(curl -s https://www.cloudflare.com/ips-v6)
sorted=($(printf '%s\n' "${ips[@]}"|sort))
# sorted=($(printf '%s\n' "${ips[@]}"|sort -t . -n -k 1,4))
for ip in "${sorted[@]}"; do
  echo "$ip"
done
echo
