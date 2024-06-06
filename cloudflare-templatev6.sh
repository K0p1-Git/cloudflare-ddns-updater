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
ttl=3600
proxy="false"

###############  SCRIPT CONFIGURATION  ###############
# @static_IPv6_mode     - Useful if you are using EUI-64 IPv6 address with SLAAC IPv6 suffix token. (Privacy Extensions)
#                       + Or some kind of static IPv6 assignment from DHCP server configuration, etc
#                       + If set to false, the IPv6 address will be acquired from external services
# @last_notable_hexes   - Used with `static_IPv6_mode`. Configure this to target what specific IPv6 address to search for
#                       + E.g. Your global primary IPv6 address is 2404:6800:4001:80e::59ec:ab12:34cd, then
#                       + You can put values (i.e. static suffixes) such as "34cd", "ab12:34cd" and etc
# @log_header_name      - Header name used for logs
# -------------------------------------------------- #
static_IPv6_mode="false"
last_notable_hexes="ffff:ffff"
log_header_name="DDNS Updater_v6"

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
## Make sure we have a valid IPv6 connection
################################################
if ! { curl -6 -s --head --fail https://ipv6.google.com >/dev/null; }; then
    logger -s "$log_header_name: Unable to establish a valid IPv6 connection to a known host."
    exit 1
fi

################################################
## Finding our IPv6 address
################################################
# Regex credits to https://stackoverflow.com/a/17871737
ipv6_regex="(([0-9a-fA-F]{1,4}:){7,7}[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,7}:|([0-9a-fA-F]{1,4}:){1,6}:[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,5}(:[0-9a-fA-F]{1,4}){1,2}|([0-9a-fA-F]{1,4}:){1,4}(:[0-9a-fA-F]{1,4}){1,3}|([0-9a-fA-F]{1,4}:){1,3}(:[0-9a-fA-F]{1,4}){1,4}|([0-9a-fA-F]{1,4}:){1,2}(:[0-9a-fA-F]{1,4}){1,5}|[0-9a-fA-F]{1,4}:((:[0-9a-fA-F]{1,4}){1,6})|:((:[0-9a-fA-F]{1,4}){1,7}|:)|fe80:(:[0-9a-fA-F]{0,4}){0,4}%[0-9a-zA-Z]{1,}|::(ffff(:0{1,4}){0,1}:){0,1}((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])|([0-9a-fA-F]{1,4}:){1,4}:((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9]))"

if $static_IPv6_mode; then
    # Test whether 'ip' command is available
    if { command -v "ip" &>/dev/null; }; then
        ip=$(ip -6 -o addr show scope global primary -deprecated | grep -oE "$ipv6_regex" | grep -oE ".*($last_notable_hexes)$")
    else
        # Fall back to 'ifconfig' command
        ip=$(ifconfig | grep -oE "$ipv6_regex" | grep -oE ".*($last_notable_hexes)$")
    fi
else
    # Use external services to discover our system's preferred IPv6 address
    ip=$(curl -s -6 https://cloudflare.com/cdn-cgi/trace | grep -E '^ip')
    ret=$?
    if [[ ! $ret == 0 ]]; then # In the case that cloudflare failed to return an ip.
        # Attempt to get the ip from other websites.
        ip=$(curl -s -6 https://api64.ipify.org || curl -s -6 https://ipv6.icanhazip.com)
    else
        # Extract just the ip from the ip line from cloudflare.
        ip=$(echo $ip | sed -E "s/^ip=($ipv6_regex)$/\1/")
    fi
fi

# Check point: Make sure the collected IPv6 address is valid
if [[ ! $ip =~ ^$ipv6_regex$ ]]; then
    logger -s "$log_header_name: Failed to find a valid IPv6 address."
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
## Seek for the AAAA record
################################################
logger "$log_header_name: Check Initiated"
record=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$zone_identifier/dns_records?type=AAAA&name=$record_name" \
    -H "X-Auth-Email: $auth_email" \
    -H "$auth_header $auth_key" \
    -H "Content-Type: application/json")

################################################
## Check if the domain has an AAAA record
################################################
if [[ $record == *"\"count\":0"* ]]; then
    logger -s "$log_header_name: Record does not exist, perhaps create one first? (${ip} for ${record_name})"
    exit 1
fi

################################################
## Get existing IP
################################################
old_ip=$(echo "$record" | sed -E 's/.*"content":"'${ipv6_regex}'".*/\1/')

# Make sure the extracted IPv6 address is valid
if [[ ! $old_ip =~ ^$ipv6_regex$ ]]; then
    logger -s "$log_header_name: Unable to extract existing IPv6 address from DNS record."
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
    --data "{\"content\":\"$ip\",\"ttl\":$ttl,\"proxied\":$proxy}")

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
                \"text\": \"$sitename Updated: $record_name's new IPv6 Address is $ip\"
            }"
    fi
    if [[ $discorduri != "" ]]; then
        curl -i -H "Accept: application/json" -H "Content-Type:application/json" -X POST \
            --data-raw "{
                \"content\": \"$sitename Updated: $record_name's new IPv6 Address is $ip\"
            }" $discorduri
    fi
    exit 0
    ;;
esac
