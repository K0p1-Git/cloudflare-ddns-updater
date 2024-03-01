#!/bin/bash
## change to "bin/sh" when necessary

##############  CLOUDFLARE CREDENTIALS  ##############
# @auth_email           - The email used to login 'https://dash.cloudflare.com'
# @auth_method          - Set to "global" for Global API Key or "token" for Scoped API Token
# @auth_key             - Your API Token or Global API Key
# @zone_identifier      - Can be found in the "Overview" tab of your domain
# -------------------------------------------------- #
auth_email=""
auth_method="token"
auth_key=""
zone_identifier=""

#############  DNS RECORD CONFIGURATION  #############
# @record_name          - Which record you want to be synced
# @ttl                  - DNS TTL (seconds), can be set between (30 if enterprise) 60 and 86400 seconds, or 1 for Automatic
# @proxy                - Set the proxy to true or false
# -------------------------------------------------- #
record_name=""
ttl="3600"
proxy="false"

###############  SCRIPT CONFIGURATION  ###############
# @log_header_name      - Header name used for logs
# -------------------------------------------------- #
log_header_name="DDNS Updater"

#############  WEBHOOKS CONFIGURATION  ###############
# @sitename             - Title of site "Example Site"
# @slackchannel         - Slack Channel #example
# @slackuri             - URI for Slack WebHook "https://hooks.slack.com/services/xxxxx"
# @discorduri           - URI for Discord WebHook "https://discordapp.com/api/webhooks/xxxxx"
# -------------------------------------------------- #
sitename=""
slackchannel=""
slackuri=""
discorduri=""

################################################
## Make sure we have a valid IPv4 connection
################################################
if ! { curl -4 -s --head --fail https://ipv4.google.com >/dev/null; }; then
    logger -s "$log_header_name: Unable to establish a valid IPv4 connection to a known host."
    exit 1
fi

################################################
## Finding our IPv4 address
################################################
ip=$(curl -s -4 https://api.ipify.org || curl -s -4 https://ipv4.icanhazip.com)

# Check point: Make sure the collected IPv4 address is valid
ipv4_regex='([01]?[0-9]?[0-9]|2[0-4][0-9]|25[0-5])\.([01]?[0-9]?[0-9]|2[0-4][0-9]|25[0-5])\.([01]?[0-9]?[0-9]|2[0-4][0-9]|25[0-5])\.([01]?[0-9]?[0-9]|2[0-4][0-9]|25[0-5])'
if [[ ! $ip =~ ^$ipv4_regex$ ]]; then
    logger -s "$log_header_name: Failed to find a valid IPv4 address."
    exit 1
fi

################################################
## Check and set the proper auth header
################################################
if [[ "${auth_method}" == "global" ]]; then
    auth_header="X-Auth-Key:"
else
    auth_header="Authorization: Bearer"
fi

################################################
## Seek for the A record
################################################
logger "$log_header_name: Check Initiated"
record=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$zone_identifier/dns_records?type=A&name=$record_name" \
    -H "X-Auth-Email: $auth_email" \
    -H "$auth_header $auth_key" \
    -H "Content-Type: application/json")

################################################
## Check if the domain has an A record
################################################
if [[ $record == *"\"count\":0"* ]]; then
    logger -s "$log_header_name: Record does not exist, perhaps create one first? (${ip} for ${record_name})"
    exit 1
fi

################################################
## Get existing IP
################################################
old_ip=$(echo "$record" | sed -E 's/.*"content":"(([0-9]{1,3}\.){3}[0-9]{1,3})".*/\1/')

# Make sure the extracted IPv4 address is valid
if [[ ! $old_ip =~ ^$ipv4_regex$ ]]; then
    logger -s "$log_header_name: Unable to extract existing IPv4 address from DNS record."
    exit 1
fi

# Compare if they're the same
if [[ $ip == $old_ip ]]; then
    logger "$log_header_name: IP ($ip) for ${record_name} has not changed."
    exit 0
fi

################################################
## Set the record identifier from result
################################################
record_identifier=$(echo "$record" | sed -E 's/.*"id":"([A-Za-z0-9_]+)".*/\1/')

################################################
## Change the IP@Cloudflare using the API
################################################
update=$(curl -s -X PATCH "https://api.cloudflare.com/client/v4/zones/$zone_identifier/dns_records/$record_identifier" \
    -H "X-Auth-Email: $auth_email" \
    -H "$auth_header $auth_key" \
    -H "Content-Type: application/json" \
    --data "{\"content\":\"$ip\",\"ttl\":\"$ttl\",\"proxied\":$proxy}")

################################################
## Report the status
################################################
case "$update" in
*"\"success\":false"*)
    echo -e "$log_header_name: $ip $record_name DDNS failed for $record_identifier ($ip). DUMPING RESULTS:\n$update" | logger -s
    if [[ $slackuri != "" ]]; then
        curl -L -X POST $slackuri \
            --data-raw "{
                \"channel\": \"$slackchannel\",
                \"text\": \"$sitename DDNS Update Failed: $record_name: $record_identifier ($ip).\"
            }"
    fi
    if [[ $discorduri != "" ]]; then
        curl -i -H "Accept: application/json" -H "Content-Type:application/json" -X POST \
            --data-raw "{
                \"content\": \"$sitename DDNS Update Failed: $record_name: $record_identifier ($ip).\"
            }" $discorduri
    fi
    exit 1
    ;;
*)
    logger "$log_header_name: $ip $record_name DDNS updated."
    if [[ $slackuri != "" ]]; then
        curl -L -X POST $slackuri \
            --data-raw "{
                \"channel\": \"$slackchannel\",
                \"text\": \"$sitename Updated: $record_name's new IPv4 Address is $ip\"
            }"
    fi
    if [[ $discorduri != "" ]]; then
        curl -i -H "Accept: application/json" -H "Content-Type:application/json" -X POST \
            --data-raw "{
                \"content\": \"$sitename Updated: $record_name's new IPv4 Address is $ip\"
            }" $discorduri
    fi
    exit 0
    ;;
esac
