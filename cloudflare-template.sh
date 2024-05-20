#!/bin/bash
## change to "bin/sh" when necessary

# Set client secrets location.
# From: https://www.reddit.com/r/bash/comments/puujxk/comment/he7bz9s/
API_KEY_DIR=${XDG_CONF_HOME:-$HOME/.config}/cloudflare

# Create a directory for client secrets if it does not exist.
if [ ! -d "${API_KEY_DIR}" ]; then
    mkdir -p "${API_KEY_DIR}"
    SECRETS_FILE=${API_KEY_DIR}/secrets.env

    # Create a secrets.env file template.
    touch ${SECRETS_FILE}
    echo -en "#/bin/bash\n\n# These are secrets used by the 'cloudflare-ddns-updater' script.\n\n" > ${SECRETS_FILE}

    echo "CLOUDFLARE_AUTH_EMAIL=\"\"                                       # The email used to login 'https://dash.cloudflare.com'" >> ${SECRETS_FILE}
    echo "CLOUDFLARE_AUTH_METHOD=\"token\"                                 # Set to "global" for Global API Key or "token" for Scoped API Token" >> ${SECRETS_FILE}
    echo "CLOUDFLARE_AUTH_KEY=\"\"                                         # Your API Token or Global API Key" >> ${SECRETS_FILE}
    echo "CLOUDFLARE_ZONE_IDENTIFIER=\"\"                                  # Can be found in the "Overview" tab of your domain" >> ${SECRETS_FILE}
    echo "CLOUDFLARE_RECORD_NAME=\"\"                                      # Which record you want to be synced (hint: the fully-qualified domain name)" >> ${SECRETS_FILE}
    echo "CLOUDFLARE_TTL=\"3600\"                                          # Set the DNS TTL (seconds)" >> ${SECRETS_FILE}
    echo "CLOUDFLARE_PROXY=\"false\"                                       # Set the proxy to true or false" >> ${SECRETS_FILE}
    echo "CLOUDFLARE_SITENAME=\"\"                                         # Title of site \"Example Site\" used in Slack and/or Discord notifications" >> ${SECRETS_FILE}
    echo "CLOUDFLARE_SLACKCHANNEL=\"\"                                     # Slack Channel #example" >> ${SECRETS_FILE}
    echo "CLOUDFLARE_SLACKURI=\"\"                                         # URI for Slack WebHook "https://hooks.slack.com/services/xxxxx"" >> ${SECRETS_FILE}
    echo "CLOUDFLARE_DISCORDURI=\"\"                                       # URI for Discord WebHook "https://discordapp.com/api/webhooks/xxxxx"" >> ${SECRETS_FILE}

    echo "No client secrets file was found. Please fill in the values in ${SECRETS_FILE}"
    exit
fi

SECRETS_FILE="${API_KEY_DIR}/secrets.env"

# Load client secrets.
. ${SECRETS_FILE}

###########################################
## Check if we have a public IP
###########################################
ipv4_regex='([01]?[0-9]?[0-9]|2[0-4][0-9]|25[0-5])\.([01]?[0-9]?[0-9]|2[0-4][0-9]|25[0-5])\.([01]?[0-9]?[0-9]|2[0-4][0-9]|25[0-5])\.([01]?[0-9]?[0-9]|2[0-4][0-9]|25[0-5])'
ip=$(curl -s -4 https://cloudflare.com/cdn-cgi/trace | grep -E '^ip'); ret=$?
if [[ ! $ret == 0 ]]; then # In the case that cloudflare failed to return an ip.
    # Attempt to get the ip from other websites.
    ip=$(curl -s https://api.ipify.org || curl -s https://ipv4.icanhazip.com)
else
    # Extract just the ip from the ip line from cloudflare.
    ip=$(echo $ip | sed -E "s/^ip=($ipv4_regex)$/\1/")
fi

# Use regex to check for proper IPv4 format.
if [[ ! $ip =~ ^$ipv4_regex$ ]]; then
    logger -s "DDNS Updater: Failed to find a valid IP."
    exit 2
fi

###########################################
## Check and set the proper auth header
###########################################
if [[ "${CLOUDFLARE_AUTH_METHOD}" == "global" ]]; then
  auth_header="X-Auth-Key:"
else
  auth_header="Authorization: Bearer"
fi

###########################################
## Seek for the A record
###########################################

logger "DDNS Updater: Check Initiated"
record=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_IDENTIFIER}/dns_records?type=A&name=${CLOUDFLARE_RECORD_NAME}" \
                      -H "X-Auth-Email: ${CLOUDFLARE_AUTH_EMAIL}" \
                      -H "$auth_header ${CLOUDFLARE_AUTH_KEY}" \
                      -H "Content-Type: application/json")
###########################################
## Check if the domain has an A record
###########################################
if [[ $record == *"\"count\":0"* ]]; then
  logger -s "DDNS Updater: Record does not exist, perhaps create one first? (${ip} for ${CLOUDFLARE_RECORD_NAME})"
  exit 1
fi

###########################################
## Get existing IP
###########################################
old_ip=$(echo "$record" | sed -E 's/.*"content":"(([0-9]{1,3}\.){3}[0-9]{1,3})".*/\1/')
# Compare if they're the same
if [[ $ip == $old_ip ]]; then
  logger "DDNS Updater: IP ($ip) for ${CLOUDFLARE_RECORD_NAME} has not changed."
  exit 0
fi

###########################################
## Set the record identifier from result
###########################################
record_identifier=$(echo "$record" | sed -E 's/.*"id":"([A-Za-z0-9_]+)".*/\1/')

###########################################
## Change the IP@Cloudflare using the API
###########################################
update=$(curl -s -X PATCH "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_IDENTIFIER}/dns_records/$record_identifier" \
                     -H "X-Auth-Email: ${CLOUDFLARE_AUTH_EMAIL}" \
                     -H "$auth_header ${CLOUDFLARE_AUTH_KEY}" \
                     -H "Content-Type: application/json" \
                     --data "{\"type\":\"A\",\"name\":\"${CLOUDFLARE_RECORD_NAME}\",\"content\":\"$ip\",\"ttl\":\"${CLOUDFLARE_TTL}\",\"proxied\":${CLOUDFLARE_PROXY}}")

###########################################
## Report the status
###########################################
case "$update" in
*"\"success\":false"*)
  echo -e "DDNS Updater: $ip ${CLOUDFLARE_RECORD_NAME} DDNS failed for $record_identifier ($ip). DUMPING RESULTS:\n$update" | logger -s 
  if [[ ${CLOUDFLARE_SLACK_URI} != "" ]]; then
    curl -L -X POST ${CLOUDFLARE_SLACK_URI} \
    --data-raw '{
      "channel": "'${CLOUDFLARE_SLACKCHANNEL}'",
      "text" : "'"${CLOUDFLARE_SITENAME}"' DDNS Update Failed: '${CLOUDFLARE_RECORD_NAME}': '$record_identifier' ('$ip')."
    }'
  fi
  if [[ ${CLOUDFLARE_DISCORD_URI} != "" ]]; then
    curl -i -H "Accept: application/json" -H "Content-Type:application/json" -X POST \
    --data-raw '{
      "content" : "'"${CLOUDFLARE_SITENAME}"' DDNS Update Failed: '${CLOUDFLARE_RECORD_NAME}': '$record_identifier' ('$ip')."
    }' ${CLOUDFLARE_DISCORD_URI}
  fi
  exit 1;;
*)
  logger "DDNS Updater: $ip ${CLOUDFLARE_RECORD_NAME} DDNS updated."
  if [[ ${CLOUDFLARE_SLACK_URI} != "" ]]; then
    curl -L -X POST ${CLOUDFLARE_SLACK_URI} \
    --data-raw '{
      "channel": "'${CLOUDFLARE_SLACKCHANNEL}'",
      "text" : "'"${CLOUDFLARE_SITENAME}"' Updated: '${CLOUDFLARE_RECORD_NAME}''"'"'s'""' new IP Address is '$ip'"
    }'
  fi
  if [[ ${CLOUDFLARE_DISCORD_URI} != "" ]]; then
    curl -i -H "Accept: application/json" -H "Content-Type:application/json" -X POST \
    --data-raw '{
      "content" : "'"${CLOUDFLARE_SITENAME}"' Updated: '${CLOUDFLARE_RECORD_NAME}''"'"'s'""' new IP Address is '$ip'"
    }' ${CLOUDFLARE_DISCORD_URI}
  fi
  exit 0;;
esac

unset CLOUDFLARE_AUTH_EMAIL=""
unset CLOUDFLARE_AUTH_METHOD="TOKEN"
unset CLOUDFLARE_AUTH_KEY=""
unset CLOUDFLARE_ZONE_IDENTIFIER=""
unset CLOUDFLARE_RECORD_NAME=""
unset CLOUDFLARE_TTL="3600"
unset CLOUDFLARE_PROXY="FALSE"
unset CLOUDFLARE_SITENAME=""
unset CLOUDFLARE_SLACKCHANNEL=""
unset CLOUDFLARE_SLACKURI=""
unset CLOUDFLARE_DISCORDURI=""

