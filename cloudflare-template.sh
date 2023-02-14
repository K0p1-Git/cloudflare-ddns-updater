#!/bin/bash
## When the system shell is required, replace the first line of the script with "#!/bin/sh"

auth_email=""				# Your account e-mail address; "Example@domain.com" (https://dash.cloudflare.com)
auth_method="token"			# Your account authentication method; Set to "global" for Global API Key or "token" for Scoped API Token
auth_key=""				# Your Global API Key or Scoped API Token; Located within the "API Tokens" section of your profile
zone_identifier=""			# Your Zone Identifier ID; Located within the "Overview" section of your domain
record_name_A=""			# The name of your A record; "www.example.com"
record_name_AAAA=""			# The name of your AAAA record; "www.example.com"
ttl="1"					# Set the DNS TTL (seconds); "1" for automatic or "3600" for default
proxy="false"				# Set the Proxy Status to "true" or "false"; "true" for Proxied or "false" for DNS Only
website_name=""				# The title of your website; "Example Website"
slack_channel=""			# The name of your Slack channel; "#channel"
slack_uri=""				# The URI of your Slack Webhook; "https://hooks.slack.com/services/xxxxx"
discord_uri=""				# The URI of your Discord Webhook; "https://discordapp.com/api/webhooks/xxxxx"

#####################################
## Check for a public IPv4 address ##
#####################################
ipv4_regex='((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])'
ipv4=$(curl -s -4 https://cloudflare.com/cdn-cgi/trace | grep -E '^ip'); ret_ipv4=$?
if [[ ! $ret_ipv4 == 0 ]]; then # In the case that Cloudflare failed to return a public IPv4 address.
    # Attempt to pull the public IPv4 address from another website.
    ipv4=$(curl -s https://api.ipify.org || curl -s https://ipv4.icanhazip.com)
else
    # Use regex to extract the public IPv4 address from the "ip=" line of the JSON data provided by Cloudflare.
    ipv4=$(echo $ipv4 | sed -E "s/^ip=($ipv4_regex)$/\1/")
    ipv4_valid="0"
fi

# Use regex to check whether the returned public IPv4 address is a valid IPv4 address.
if [[ ! $ipv4 =~ ^$ipv4_regex$ ]]; then
    logger -s "DDNS Updater: Failed to return a valid public IPv4 address."
    ipv4_valid="1"
fi

#####################################
## Check for a public IPv6 address ##
#####################################
ipv6_regex='(([0-9a-fA-F]{1,4}:){7,7}[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,7}:|([0-9a-fA-F]{1,4}:){1,6}:[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,5}(:[0-9a-fA-F]{1,4}){1,2}|([0-9a-fA-F]{1,4}:){1,4}(:[0-9a-fA-F]{1,4}){1,3}|([0-9a-fA-F]{1,4}:){1,3}(:[0-9a-fA-F]{1,4}){1,4}|([0-9a-fA-F]{1,4}:){1,2}(:[0-9a-fA-F]{1,4}){1,5}|[0-9a-fA-F]{1,4}:((:[0-9a-fA-F]{1,4}){1,6})|:((:[0-9a-fA-F]{1,4}){1,7}|:)|fe80:(:[0-9a-fA-F]{0,4}){0,4}%[0-9a-zA-Z]{1,}|::(ffff(:0{1,4}){0,1}:){0,1}((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])|([0-9a-fA-F]{1,4}:){1,4}:((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9]))'
ipv6=$(curl -s -6 https://cloudflare.com/cdn-cgi/trace | grep -E '^ip'); ret_ipv6=$?
if [[ ! $ret_ipv6 == 0 ]]; then # In the case that Cloudflare failed to return a public IPv6 address.
    # Attempt to pull the public IPv6 address from another website.
    ipv6=$(curl -s https://api64.ipify.org || curl -s https://ipv6.icanhazip.com)
else
    # Use regex to extract the public IPv6 address from the "ip=" line of the JSON provided by Cloudflare.
    ipv6=$(echo $ipv6 | sed -E "s/^ip=($ipv6_regex)$/\1/")
    ipv6_valid="0"
fi

# Use regex to check whether the returned public IPv6 address is a valid IPv6 address.
if [[ ! $ipv6 =~ ^$ipv6_regex$ ]]; then
    logger -s "DDNS Updater: Failed to return a valid public IPv6 address."
    ipv6_valid="1"
fi

#############################################################
## Check the returned public IPv4 address and IPv6 address ##
#############################################################
if [[ ! $ipv4_valid == 0 && ! $ipv6_valid == 0 ]]; then # In the case that the returned IPv4 address and IPv6 address are both invalid.
    # Exit the script with exit code 2: Misuse of shell builtins.
    exit 2
fi

###################################
## Set the authentication header ##
###################################
if [[ "${auth_method}" == "global" ]]; then
    auth_header="X-Auth-Key:"
else
    auth_header="Authorization: Bearer"
fi

######################
## Get the A record ##
######################
logger "DDNS Updater: Check initiated for A record."
record_A=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$zone_identifier/dns_records?type=A&name=$record_name_A" \
                      -H "X-Auth-Email: $auth_email" \
                      -H "$auth_header $auth_key" \
                      -H "Content-Type: application/json")

####################################
## Check for an existing A record ##
####################################
if [[ $record_A == *"\"count\":0"* ]]; then
    logger -s "DDNS Updater: A record does not exist. Create one first? (${ipv4} for ${record_name_A})"
    record_A_valid="1"
else
    record_A_valid="0"
fi

#########################
## Get the AAAA record ##
#########################
logger "DDNS Updater: Check initiated for AAAA record."
record_AAAA=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$zone_identifier/dns_records?type=AAAA&name=$record_name_AAAA" \
                      -H "X-Auth-Email: $auth_email" \
                      -H "$auth_header $auth_key" \
                      -H "Content-Type: application/json")


#######################################
## Check for an existing AAAA record ##
#######################################
if [[ $record_AAAA == *"\"count\":0"* ]]; then
    logger -s "DDNS Updater: AAAA record does not exist. Create one first? (${ipv6} for ${record_name_AAAA})"
    record_AAAA_valid="1"
else
    record_AAAA_valid="0"
fi

#################################################
## Check the returned A record and AAAA record ##
#################################################
if [[ ! $record_A_valid == 0 && ! $record_AAAA_valid == 0 ]]; then # In the case both the returned A record and AAAA record do not exist.
    # Exit the script with exit code 1: General errors.
    exit 1
fi

#####################################################################
## Check the returned A record for an existing public IPv4 address ##
#####################################################################
old_ipv4=$(echo "$record_A" | sed -E 's/.*"content":"('$ipv4_regex')".*/\1/')
if [[ $ipv4 == $old_ipv4 ]]; then # Use regex to compare whether the returned public IPv4 address and existing public IPv4 address are the same.
    logger "DDNS Updater: The IPv4 address ($ipv4) for ${record_name_A} has not changed."
    old_ipv4_valid="1"
else
    old_ipv4_valid="0"
fi

########################################################################
## Check the returned AAAA record for an existing public IPv6 address ##
########################################################################
old_ipv6=$(echo "$record_AAAA" | sed -E 's/.*"content":"('$ipv6_regex')".*/\1/')
if [[ $ipv6 == $old_ipv6 ]]; then # Use regex to compare whether the returned public IPv6 address and existing public IPv6 address are the same.
    logger "DDNS Updater: The IPv6 address ($ipv6) for ${record_name_AAAA} has not changed."
    old_ipv6_valid="1"
else
    old_ipv6_valid="0"
fi

####################################################################
## Check the existing public IPv4 address and public IPv6 address ##
####################################################################
if [[ ! $record_ipv4_valid == 0 && ! $old_ipv6_valid == 0 ]]; then # In the case both the existing public IPv4 address and public IPv6 address have not changed.
    # Exit the script with exit code 0: Success.
    exit 0
fi

##################################################
## Set the A record and AAAA record identifiers ##
##################################################
record_identifier_A=$(echo "$record_A" | sed -E 's/.*"id":"(\w+)".*/\1/')
record_identifier_AAAA=$(echo "$record_AAAA" | sed -E 's/.*"id":"(\w+)".*/\1/')

####################################
## Update the public IPv4 address ##
####################################
update_ipv4=$(curl -s -X PATCH "https://api.cloudflare.com/client/v4/zones/$zone_identifier/dns_records/$record_identifier_A" \
                     -H "X-Auth-Email: $auth_email" \
                     -H "$auth_header $auth_key" \
                     -H "Content-Type: application/json" \
                     --data "{\"type\":\"A\",\"name\":\"$record_name_A\",\"content\":\"$ipv4\",\"ttl\":\"$ttl\",\"proxied\":${proxy}}")

####################################
## Update the public IPv6 address ##
####################################
update_v6=$(curl -s -X PATCH "https://api.cloudflare.com/client/v4/zones/$zone_identifier/dns_records/$record_identifier_AAAA" \
                     -H "X-Auth-Email: $auth_email" \
                     -H "$auth_header $auth_key" \
                     -H "Content-Type: application/json" \
                     --data "{\"type\":\"AAAA\",\"name\":\"$record_name_AAAA\",\"content\":\"$ipv6\",\"ttl\":\"$ttl\",\"proxied\":${proxy}}")

#########################################################
## Report the update status of the public IPv4 address ##
#########################################################
case "$update_ipv4" in
*"\"success\":false"*)
    echo -e "DDNS Updater: $ipv4 $record_name_A DDNS failed for $record_identifier_A ($ipv4). Dumping results:\n$update_ipv4" | logger -s
    if [[ $slack_uri != "" ]]; then
        curl -L -X POST $slack_uri \
        --data-raw '{
          "channel": "'$slack_channel'",
          "text" : "'"$website_name"' DDNS Updater: Failed for '$record_name_A': '$record_identifier_A' ('$ipv4')."
        }'
    fi
    if [[ $discord_uri != "" ]]; then
        curl -i -H "Accept: application/json" -H "Content-Type:application/json" -X POST \
        --data-raw '{
          "content" : "'"$website_name"' DDNS Updater: Failed for '$record_name_A': '$record_identifier_A' ('$ipv4')."
        }' $discord_uri
    fi
    update_ipv4_valid="1"
    ;;
*)
    if [[ $slack_uri != "" ]]; then
        curl -L -X POST $slack_uri \
        --data-raw '{
          "channel": "'$slack_channel'",
          "text" : "'"$website_name"' Updated: '$record_name_A''"'"'s'""' new IP Address is '$ipv4'"
        }'
    fi
    if [[ $discord_uri != "" ]]; then
      curl -i -H "Accept: application/json" -H "Content-Type:application/json" -X POST \
      --data-raw '{
        "content" : "'"$website_name"' Updated: '$record_name_A''"'"'s'""' new IP Address is '$ipv4'"
      }' $discord_uri
    fi
    logger "DDNS Updater: $ipv4 $record_name_A DDNS updated successfully."
    update_ipv4_valid="0"
    ;;
esac

#########################################################
## Report the update status of the public IPv6 address ##
#########################################################
case "$update_ipv6" in
*"\"success\":false"*)
    echo -e "DDNS Updater: $ipv6 $record_name_AAAA DDNS failed for $record_identifier_AAAA ($ipv6). Dumping results:\n$update_ipv6" | logger -s
    if [[ $slack_uri != "" ]]; then
      curl -L -X POST $slack_uri \
      --data-raw '{
        "channel": "'$slack_channel'",
        "text" : "'"$website_name"' DDNS Updater: Failed for '$record_name_AAAA': '$record_identifier_AAAA' ('$ipv6')."
      }'
    fi
    if [[ $discord_uri != "" ]]; then
      curl -i -H "Accept: application/json" -H "Content-Type:application/json" -X POST \
      --data-raw '{
        "content" : "'"$website_name"' DDNS Updater: Failed for '$record_name_AAAA': '$record_identifier_AAAA' ('$ipv6')."
      }' $discord_uri
    fi
    update_ipv6_valid="1"
    ;;
*)
    if [[ $slack_uri != "" ]]; then
      curl -L -X POST $slack_uri \
      --data-raw '{
        "channel": "'$slack_channel'",
        "text" : "'"$website_name"' Updated: '$record_name_AAAA''"'"'s'""' new IPv6 Address is '$ipv6'"
      }'
    fi
    if [[ $discord_uri != "" ]]; then
      curl -i -H "Accept: application/json" -H "Content-Type:application/json" -X POST \
      --data-raw '{
        "content" : "'"$website_name"' Updated: '$record_name_AAAA''"'"'s'""' new IPv6 Address is '$ipv6'"
      }' $discord_uri
    fi
    logger "DDNS Updater: $ipv6 $record_name_AAAA DDNS updated successfully."
    update_ipv6_valid="0"
    ;;
esac

################################################################################
## Check the update status of the public IPv4 address and public IPv6 address ##
################################################################################
if [[ ! $update_ipv4_valid == 0 || ! $update_ipv6_valid == 0 ]]; then # In the case the update status of either the public IPv4 address or public IPv6 address are invalid.
    # Exit the script with exit code 1: General errors.
    exit 1
else
    # Exit the script with exit code 0: Success.
    exit 0
fi

# End of the script
# Exit the script with exit code 0: Success.
exit 0
