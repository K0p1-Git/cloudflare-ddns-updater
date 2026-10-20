#!/bin/bash
## change to "bin/sh" when necessary

auth_email=""                                       # The email used to login 'https://dash.cloudflare.com'
auth_method="token"                                 # Set to "global" for Global API Key or "token" for Scoped API Token
auth_key=""                                         # Your API Token or Global API Key
zone_identifier=""                                  # Can be found in the "Overview" tab of your domain
record_name=""                                      # Which record you want to be synced
ttl=3600                                            # Set the DNS TTL (seconds)
proxy="false"                                       # Set the proxy to true or false
sitename=""                                         # Title of site "Example Site"
slackchannel=""                                     # Slack Channel #example
slackuri=""                                         # URI for Slack WebHook "https://hooks.slack.com/services/xxxxx"
discorduri=""                                       # URI for Discord WebHook "https://discordapp.com/api/webhooks/xxxxx"


###########################################
## Prevent overlapping runs
###########################################
lock_file="/var/lock/cloudflare-ddns.lock"
exec 9>"$lock_file" || { logger -s "DDNS Updater: Unable to open lock file $lock_file."; exit 1; }
if ! flock -n 9; then
  logger -s "DDNS Updater: Another instance is already running, exiting."
  exit 0
fi

# Timeouts and retries applied to every curl call
curl_opts=(--max-time 10 --retry 2)

###########################################
## Check if we have a public IP
###########################################
REGEX_IPV4="^(0*(1?[0-9]{1,2}|2([0-4][0-9]|5[0-5]))\.){3}0*(1?[0-9]{1,2}|2([0-4][0-9]|5[0-5]))$"
IP_SERVICES=(
  "https://api.ipify.org"
  "https://ipv4.icanhazip.com"
  "https://ipinfo.io/ip"
)

# Try all the ip services for a valid IPv4 address
for service in ${IP_SERVICES[@]}; do
  RAW_IP=$(curl -s "${curl_opts[@]}" $service)
  if [[ $RAW_IP =~ $REGEX_IPV4 ]]; then
    CURRENT_IP=$BASH_REMATCH
    logger -s "DDNS Updater: Fetched IP $CURRENT_IP"
    break
  else
    logger -s "DDNS Updater: IP service $service failed."
  fi
done

# Exit if IP fetching failed
if [[ -z "$CURRENT_IP" ]]; then
  logger -s "DDNS Updater: Failed to find a valid IP."
  exit 2
fi

###########################################
## Check and set the proper auth header
###########################################
if [[ "${auth_method}" == "global" ]]; then
  auth_header="X-Auth-Key:"
else
  auth_header="Authorization: Bearer"
fi

###########################################
## Seek for the A record
###########################################

logger "DDNS Updater: Check Initiated"
record=$(curl -s "${curl_opts[@]}" -X GET "https://api.cloudflare.com/client/v4/zones/$zone_identifier/dns_records?type=A&name=$record_name" \
                      -H "X-Auth-Email: $auth_email" \
                      -H "$auth_header $auth_key" \
                      -H "Content-Type: application/json")
lookup_status=$?

# Exit if the lookup failed or Cloudflare did not report success
if [[ $lookup_status -ne 0 || -z "$record" || $record != *"\"success\":true"* ]]; then
  logger -s "DDNS Updater: Record lookup failed for ${record_name} (curl exit ${lookup_status}). Response: ${record}"
  exit 1
fi

###########################################
## Check if the domain has an A record
###########################################
if [[ $record == *"\"count\":0"* ]]; then
  logger -s "DDNS Updater: Record does not exist, perhaps create one first? (${CURRENT_IP} for ${record_name})"
  exit 1
fi

###########################################
## Get existing IP
###########################################
old_ip=$(echo "$record" | sed -E 's/.*"content":"(([0-9]{1,3}\.){3}[0-9]{1,3})".*/\1/')
# Compare if they're the same
if [[ $CURRENT_IP == $old_ip ]]; then
  logger "DDNS Updater: IP ($CURRENT_IP) for ${record_name} has not changed."
  exit 0
fi

###########################################
## Set the record identifier from result
###########################################
record_identifier=$(echo "$record" | sed -E 's/.*"id":"([A-Za-z0-9_]+)".*/\1/')

# Exit if either value is empty or sed found no match (returns the whole record)
if [[ -z "$old_ip" || -z "$record_identifier" || "$old_ip" == "$record" || "$record_identifier" == "$record" ]]; then
  logger -s "DDNS Updater: Unable to extract existing IP or record ID for ${record_name}, not updating."
  exit 1
fi

###########################################
## Change the IP@Cloudflare using the API
###########################################
update=$(curl -s "${curl_opts[@]}" -X PATCH "https://api.cloudflare.com/client/v4/zones/$zone_identifier/dns_records/$record_identifier" \
                     -H "X-Auth-Email: $auth_email" \
                     -H "$auth_header $auth_key" \
                     -H "Content-Type: application/json" \
                     --data "{\"type\":\"A\",\"name\":\"$record_name\",\"content\":\"$CURRENT_IP\",\"ttl\":$ttl,\"proxied\":${proxy}}")
update_status=$?

###########################################
## Report the status
###########################################
# Only an explicit success counts; an empty or malformed response is a failure
case "$update" in
*"\"success\":true"*)
  logger "DDNS Updater: $CURRENT_IP $record_name DDNS updated."
  if [[ $slackuri != "" ]]; then
    curl "${curl_opts[@]}" -L -X POST $slackuri \
    --data-raw '{
      "channel": "'$slackchannel'",
      "text" : "'"$sitename"' Updated: '$record_name''"'"'s'""' new IP Address is '$CURRENT_IP'"
    }'
  fi
  if [[ $discorduri != "" ]]; then
    curl "${curl_opts[@]}" -i -H "Accept: application/json" -H "Content-Type:application/json" -X POST \
    --data-raw '{
      "content" : "'"$sitename"' Updated: '$record_name''"'"'s'""' new IP Address is '$CURRENT_IP'"
    }' $discorduri
  fi
  exit 0;;
*)
  echo -e "DDNS Updater: $CURRENT_IP $record_name DDNS failed for $record_identifier ($CURRENT_IP) (curl exit $update_status). DUMPING RESULTS:\n$update" | logger -s
  if [[ $slackuri != "" ]]; then
    curl "${curl_opts[@]}" -L -X POST $slackuri \
    --data-raw '{
      "channel": "'$slackchannel'",
      "text" : "'"$sitename"' DDNS Update Failed: '$record_name': '$record_identifier' ('$CURRENT_IP')."
    }'
  fi
  if [[ $discorduri != "" ]]; then
    curl "${curl_opts[@]}" -i -H "Accept: application/json" -H "Content-Type:application/json" -X POST \
    --data-raw '{
      "content" : "'"$sitename"' DDNS Update Failed: '$record_name': '$record_identifier' ('$CURRENT_IP')."
    }' $discorduri
  fi
  exit 1;;
esac
