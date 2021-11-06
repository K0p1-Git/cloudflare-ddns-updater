#!/bin/bash
## change to "bin/sh" when necessary

auth_email=""                                      # The email used to login 'https://dash.cloudflare.com'
auth_method="token"                                # Set to "global" for Global API Key or "token" for Scoped API Token 
auth_key=""                                        # Your API Token or Global API Key
zone_identifier=""                                 # Can be found in the "Overview" tab of your domain
record_name=""                                     # Which record you want to be synced
ttl="3600"                                         # Set the DNS TTL (seconds)
proxy=false                                        # Set the proxy to true or false
slacksitename=""                                   # Title of site "Example Site"
slackchannel=""                                    # Slack Channel #example
slackuri=""                                        # URI for Slack WebHook "https://hooks.slack.com/services/xxxxx"



###########################################
## Check if we have a public IP
###########################################
ip=$(curl -s https://api.ipify.org || curl -s https://ipv4.icanhazip.com/)

if [ "${ip}" == "" ]; then 
  logger -s "DDNS Updater: No public IP found"
  exit 1
fi

###########################################
## Check and set the proper auth header
###########################################
if [ "${auth_method}" == "global" ]; then
  auth_header="X-Auth-Key:"
else
  auth_header="Authorization: Bearer"
fi

###########################################
## Seek for the A record
###########################################

logger "DDNS Updater: Check Initiated"
record=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$zone_identifier/dns_records?type=A&name=$record_name" \
                      -H "X-Auth-Email: $auth_email" \
                      -H "$auth_header $auth_key" \
                      -H "Content-Type: application/json")

###########################################
## Check if the domain has an A record
###########################################
if [[ $record == *"\"count\":0"* ]]; then
  logger -s "DDNS Updater: Record does not exist, perhaps create one first? (${ip} for ${record_name})"
  exit 1
fi

###########################################
## Get existing IP
###########################################
old_ip=$(echo "$record" | sed -E 's/.*"content":"(([0-9]{1,3}\.){3}[0-9]{1,3})".*/\1/')
# Compare if they're the same
if [[ $ip == $old_ip ]]; then
  logger "DDNS Updater: IP ($ip) for ${record_name} has not changed."
  exit 0
fi

###########################################
## Set the record identifier from result
###########################################
record_identifier=$(echo "$record" | sed -E 's/.*"id":"(\w+)".*/\1/')

###########################################
## Change the IP@Cloudflare using the API
###########################################
update=$(curl -s -X PATCH "https://api.cloudflare.com/client/v4/zones/$zone_identifier/dns_records/$record_identifier" \
                     -H "X-Auth-Email: $auth_email" \
                     -H "$auth_header $auth_key" \
                     -H "Content-Type: application/json" \
              --data "{\"type\":\"A\",\"name\":\"$record_name\",\"content\":\"$ip\",\"ttl\":\"$ttl\",\"proxied\":${proxy}}")

###########################################
## Report the status
###########################################
case "$update" in
*"\"success\":false"*)
  logger -s "DDNS Updater: $ip $record_name DDNS failed for $record_identifier ($ip). DUMPING RESULTS:\n$update"
  if [[ $slackuri != "" ]]; then
    curl -L -X POST $slackuri \
    --data-raw '{
      "channel": "'$slackchannel'",
      "text" : "'"$slacksitename"' DDNS Update Failed: '$record_name': '$record_identifier' ('$ip')."
    }'
  fi
  exit 1;;
*)
  logger "DDNS Updater: $ip $record_name DDNS updated."
  if [[ $slackuri != "" ]]; then
    curl -L -X POST $slackuri \
    --data-raw '{
      "channel": "'$slackchannel'",
      "text" : "'"$slacksitename"' Updated: '$record_name''"'"'s'""' new IP Address is '$ip'"
    }'
  fi
  exit 0;;
esac
