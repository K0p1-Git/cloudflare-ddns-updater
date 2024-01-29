#!/bin/bash
## change to "bin/sh" when necessary

# display_help function: Displays the usage instructions for the script.
display_help(){
  logger "Usage: $0 [local|file|pass]"
  logger "  local - Load variables from this script"
  logger "  file  - Load variables from a file"
  logger "  pass  - Load variables from pass"
}

# load_variables function: Loads the required variables based on the input option.
load_variables(){
  case "$1" in
    "local")
      # Load variables from this script
      auth_email=""                                       # The email used to login 'https://dash.cloudflare.com'
      auth_method=""                                      # Set to "global" for Global API Key or "token" for Scoped API Token
      auth_key=""                                         # Your API Token or Global API Key
      zone_identifier=""                                  # Can be found in the "Overview" tab of your domain
      record_name=""                                      # Which record you want to be synced
      ttl="3600"                                          # Set the DNS TTL (seconds)
      proxy="false"                                       # Set the proxy to true or false
      sitename=""                                         # Title of site "Example Site"
      slackchannel=""                                     # Slack Channel #example
      slackuri=""                                         # URI for Slack WebHook "https://hooks.slack.com/services/xxxxx"
      discorduri=""                                       # URI for Discord WebHook "https://discordapp.com/api/webhooks/xxxxx"
      ;;
    "file")
      # Load variables from file
      CONFIG_FILE="$HOME/.cloudflare/config4.ini"

      # Check if the configuration file exists
      if [ -f "$CONFIG_FILE" ]; then
          # Load configuration from the file
          source "$CONFIG_FILE"
      else
          logger "Error: Configuration file '$CONFIG_FILE' not found."
          exit 1
      fi
      ;;
    "pass")
      # Load variables from pass
      source <(pass credentials/cloudflare)
      ;;
    *)
      logger "Invalid load_variables option"
      exit 1
      ;;
  esac
}

# validate_variables function: Validates the required variables.
validate_variables(){
  # Validate required variables
  if [[ -z $auth_email || -z $auth_key || -z $zone_identifier || -z $record_name ]]; then
    logger "Missing required variables. Please provide values for 'auth_email', 'auth_key', 'zone_identifier', and 'record_name'."
    exit 1
  fi
}

# check_ipv4_is_available function: Checks if IPv4 is available and retrieves the IP address.
check_ipv4_is_available(){
  ipv4_regex='([01]?[0-9]?[0-9]|2[0-4][0-9]|25[0-5])\.([01]?[0-9]?[0-9]|2[0-4][0-9]|25[0-5])\.([01]?[0-9]?[0-9]|2[0-4][0-9]|25[0-5])\.([01]?[0-9]?[0-9]|2[0-4][0-9]|25[0-5])'

  ip=$(curl -s -4 https://cloudflare.com/cdn-cgi/trace | grep -E '^ip=' | cut -d '=' -f 2)

  if [[ -z $ip ]]; then
    # Cloudflare did not return an IP, try other sources.
    ip=$(curl -s https://api.ipify.org || curl -s https://ipv4.icanhazip.com)
  else
    # Use regex to check for proper IPv4 format.
    if [[ ! $ip =~ ^$ipv4_regex$ ]]; then
      logger -s "DDNS Updater: Failed to find a valid IP from Cloudflare."
      exit 1
    fi
  fi
}

# set_auth_headers function: Sets the authentication headers based on the authentication method.
set_auth_headers(){
  if [[ "${auth_method}" == "global" ]]; then
    auth_header="X-Auth-Key:"
  else
    auth_header="Authorization: Bearer"
  fi
}

# check_if_a_record_exists function: Checks if the DNS record exists in Cloudflare.
check_if_a_record_exists(){
  logger "DDNS Updater: Check Initiated"
  record=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$zone_identifier/dns_records?type=A&name=$record_name" \
                        -H "X-Auth-Email: $auth_email" \
                        -H "$auth_header $auth_key" \
                        -H "Content-Type: application/json")

  if [[ $record == *"\"count\":0"* ]]; then
    logger -s "DDNS Updater: Record does not exist, perhaps create one first? (${ip} for ${record_name})"
    exit 1
  fi
}

# get_current_ip_from_cloudflare function: Retrieves the current IP address from Cloudflare.
get_current_ip_from_cloudflare(){
  old_ip=$(logger "$record" | sed -E 's/.*"content":"(([0-9]{1,3}\.){3}[0-9]{1,3})".*/\1/')
  # Compare if they're the same
  if [[ $ip == $old_ip ]]; then
    logger "DDNS Updater: IP ($ip) for ${record_name} has not changed."
    exit 0
  fi
}

# update_ip_on_cloudflare function: Updates the IP address on Cloudflare.
update_ip_on_cloudflare(){
  record_identifier=$(logger "$record" | sed -E 's/.*"id":"([A-Za-z0-9_]+)".*/\1/')

  update=$(curl -s -X PATCH "https://api.cloudflare.com/client/v4/zones/$zone_identifier/dns_records/$record_identifier" \
                      -H "X-Auth-Email: $auth_email" \
                      -H "$auth_header $auth_key" \
                      -H "Content-Type: application/json" \
                      --data "{\"type\":\"A\",\"name\":\"$record_name\",\"content\":\"$ip\",\"ttl\":\"$ttl\",\"proxied\":${proxy}}")
}

# send_webhooks function: Sends webhooks to Slack and Discord.
send_webhooks(){
  case "$update" in
  *"\"success\":false"*)
    logger -e "DDNS Updater: $ip $record_name DDNS failed for $record_identifier ($ip). DUMPING RESULTS:\n$update" | logger -s 
    if [[ $slackuri != "" ]]; then
      curl -L -X POST $slackuri \
      --data-raw '{
        "channel": "'$slackchannel'",
        "text" : "'"$sitename"' DDNS Update Failed: '$record_name': '$record_identifier' ('$ip')."
      }'
    fi
    if [[ $discorduri != "" ]]; then
      curl -i -H "Accept: application/json" -H "Content-Type:application/json" -X POST \
      --data-raw '{
        "content" : "'"$sitename"' DDNS Update Failed: '$record_name': '$record_identifier' ('$ip')."
      }' $discorduri
    fi
    exit 1;;
  *)
    logger "DDNS Updater: $ip $record_name DDNS updated."
    if [[ $slackuri != "" ]]; then
      curl -L -X POST $slackuri \
      --data-raw '{
        "channel": "'$slackchannel'",
        "text" : "'"$sitename"' Updated: '$record_name''"'"'s'""' new IP Address is '$ip'"
      }'
    fi
    if [[ $discorduri != "" ]]; then
      curl -i -H "Accept: application/json" -H "Content-Type:application/json" -X POST \
      --data-raw '{
        "content" : "'"$sitename"' Updated: '$record_name''"'"'s'""' new IP Address is '$ip'"
      }' $discorduri
    fi
    exit 0;;
  esac
}

# main function: Entry point of the script.
main(){
  validate_variables
  check_ipv4_is_available
  set_auth_headers
  check_if_a_record_exists
  get_current_ip_from_cloudflare
  update_ip_on_cloudflare
  send_webhooks
}

# switch for environment variables loading
case "$1" in
  "local"|"file"|"pass")
    load_variables "$1"
    main
    ;;
  *)
    display_help
    exit 1
    ;;
esac