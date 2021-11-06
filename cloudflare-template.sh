##!/bin/bash
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

#tolerant_is_set=0
top_exit_code=-1;
#argument_total=$#
#tolerant_is_set=false; 

debug_output_echo () {
  if [ ! -z $debug_mode_active ]; then
    if [ $debug_mode_active -eq 1 ]; then
      echo -e $debug_output
    fi
  fi
}
exit_code () {
  if [ $top_exit_code -lt $excode ]; then
    top_exit_code=$excode
  fi
   
  if [ $tolerant_is_set -eq 1 ]; then
  # Only when tolerent mode is active, it will not stop for error
    logger_output="DDNS Updater: in tolerant mode - exit [$excode]"
	debug_output+=$logger_output"\n"
    logger $logger_output
  else
  #It strict mode it will stap instantly on error
    debug_output_echo
    exit $exit_code
  fi
}

cf_ddns_ip () {
  ###########################################
  ## Check if we have a public IP
  ###########################################
  ip=$(curl -s https://api.ipify.org || curl -s https://ipv4.icanhazip.com/)
  
  if [ "${ip}" == "" ]; then 
    logger_output="DDNS Updater: No public IP found"
	debug_output+=$logger_output"\n"
    logger -s $logger_output
   # excode=1; exit_code
    #no point going on if can not get ip
    exit 1
  fi
}

cf_ddns_authheader () {
  ###########################################
  ## Check and set the proper auth header
  ###########################################
  if [ "${auth_method}" == "global" ]; then
    auth_header="X-Auth-Key:"
  else
    auth_header="Authorization: Bearer"
  fi
  debug_output+="cf_ddns_authheader : "$auth_header"\n"
 }

cf_ddns_seeka () { 
  ###########################################
  ## Seek for the A record
  ###########################################
  
  logger_output="DDNS Updater: Check Initiated"
  debug_output+=$logger_output"\n"
  logger "$logger_output"
  record=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$zone_identifier/dns_records?type=A&name=$record_name" \
                        -H "X-Auth-Email: $auth_email" \
                        -H "$auth_header $auth_key" \
                        -H "Content-Type: application/json")
  debug_output+="cf_ddns_seeka : "$record"\n"
}

cf_ddns_checka () {
  ###########################################
  ## Check if the domain has an A record
  ###########################################
  cf_nonexistsrecord=1
  if [[ $record == *"\"count\":0"* ]]; then
    logger_output="DDNS Updater: Record does not exist, perhaps create one first? (${ip} for ${record_name})"
    debug_output+=$logger_output"\n"
    logger -s $logger_output
	cf_nonexistsrecord=0
    excode=1; exit_code
   fi
}

cf_ddns_currentip () {
  ###########################################
  ## Get existing IP
  ###########################################
  old_ip=$(echo "$record" | sed -E 's/.*"content":"(([0-9]{1,3}\.){3}[0-9]{1,3})".*/\1/')
  # Compare if they're the same
  if [[ $ip == $old_ip ]]; then
    logger_output="DDNS Updater: IP ($ip) for ${record_name} has not changed."
    debug_output+=$logger_output"\n"
    logger -s $logger_output
	logger logger_output
    excode=0; exit_code
  fi
}

cf_ddns_set_identifier () {
  ###########################################
  ## Set the record identifier from result
  ###########################################
  record_identifier=$(echo "$record" | sed -E 's/.*"id":"(\w+)".*/\1/')
  debug_output+="cf_ddns_set_identifier : "$record_identifier"\n"
}

cf_ddns_update () {
  ###########################################
  ## Change the IP@Cloudflare using the API
  ###########################################
  update=$(curl -s -X PATCH "https://api.cloudflare.com/client/v4/zones/$zone_identifier/dns_records/$record_identifier" \
						-H "X-Auth-Email: $auth_email" \
						-H "$auth_header $auth_key" \
						-H "Content-Type: application/json" \
				--data "{\"type\":\"A\",\"name\":\"$record_name\",\"content\":\"$ip\",\"ttl\":\"$ttl\",\"proxied\":${proxy}}")
  debug_output+="cf_ddns_update : "$update"\n"
}

cf_ddns_status () {
  ###########################################
  ## Report the status
  ###########################################
  case "$update" in
  *"\"success\":false"*)
    logger_output="DDNS Updater: $ip $record_name DDNS failed for $record_identifier ($ip). DUMPING RESULTS:\n$update"
    debug_output+=$logger_output"\n"
    logger -s $logger_output
    curl -L -X POST $slackuri \
    --data-raw '{
      "channel": "'$slackchannel'",
      "text" : "'"$slacksitename"' DDNS Update Failed: '$record_name': '$record_identifier' ('$ip')."
    }'
    excode=1; exit_code;;
  *)
    logger_output="DDNS Updater: $ip $record_name DDNS updated."
    debug_output+=$logger_output"\n"
    logger $logger_output
    curl -L -X POST $slackuri \
    --data-raw '{
      "channel": "'$slackchannel'",
      "text" : "'"$slacksitename"' Updated: '$record_name''"'"'s'""' new IP Address is '$ip'"
    }'
    excode=0; exit_code;;
  esac
 }

cf_ddns() {
  if [ ${#ip} -eq 0 ]; then
  #Only worth getting current IP address with first domain
    cf_ddns_ip
    cf_ddns_authheader
  fi
  
  cf_ddns_seeka
  cf_ddns_checka
  if [ $cf_nonexistsrecord -eq 1 ]; then
    cf_ddns_currentip
    if [[ $ip != $old_ip ]]; then
      cf_ddns_set_identifier
      cf_ddns_update
      cf_ddns_status
    fi
  fi
}
cf_parameter_commands () {
  case "$parameter_current" in
    "-debug")
	  debug_mode_active=1
	  ;;
	"-help")
	  echo "# crontab\n"
          echo "*/5 * * * * /bin/bash /home/user/cloudflare-ddns-updater/cloudflare-init.sh"
          echo '*/5 * * * * /bin/bash /home/user/cloudflare-ddns-updater/cloudflare-init.sh mydomain.com example.com www.example.com x1.example.com'
          echo -e $output_help
	  ;;
	*)
	  echo "Unknown ***************************"
	  ;;
  esac
}

cf_err_human () {
  err_is_human=0
  
  if [ ${#auth_email} -eq 0 ]; then
    err_is_human=1
    logger_output="DDNS Updater: ERROR [auth_email] record not been defined"
	debug_output+=$logger_output"\n"
    logger -s $logger_output
  fi
  
  if [ $auth_method != "token" ] && [ $auth_method != "global" ]; then
    err_is_human=1
    logger_output='DDNS Updater: ERROR [auth_method] is invaled it has to be defined "token" "global" defined'
    debug_output+=$logger_output"\n"
    logger -s $logger_output
  fi
    
  if [ ${#auth_key} -eq 0 ]; then
    err_is_human=1
    logger_output="DDNS Updater: ERROR [auth_key] record not been defined"
	debug_output+=$logger_output"\n"
    logger -s $logger_output
  fi
    
  if [ ${#zone_identifier} -eq 0 ]; then
    err_is_human=1
    logger_output="DDNS Updater: ERROR [zone_identifier] record has not been defined"
	debug_output+=$logger_output"\n"
    logger -s $logger_output
  fi
    
  if [ ${#record_name} -eq 0 ] && [ $argument_total -eq 0 ]; then
    err_is_human=1
    logger_output="DDNS Updater: ERROR [record_name] record not has been defined"
	debug_output+=$logger_output"\n"
    logger -s $logger_output
  fi
    
  if [ -z "$tolerant_is_set" ]; then
    # if tolerant_is_set has not been set up it will be strict
    tolerant_is_set=0 
  fi
  
  if [ $tolerant_is_set -lt 0 ] || [ $tolerant_is_set -gt 1 ]; then
    err_is_human=1
    logger_output="DDNS Updater: ERROR [tolerant_is_set] can only by 0 or 1"
	debug_output+=$logger_output"\n"
    logger -s $logger_output
  fi

  if [ $err_is_human -eq 1 ]; then
    #It is done this way so all errors get disclosed    
    debug_output_echo 
    exit 1
  fi


}

argument_total=$#
tolerant_is_set=1
debug_output=""
cf_err_human


if [ $# -ne 0 ]; then
  # If a parameter has been defined in will ignore any setting in [record_name]
  parameter=("$@")
  for (( argument_depth=0 ; argument_depth < argument_total ; argument_depth++ )); do
    parameter_current=${parameter[argument_depth]}
	first_character=${parameter_current:0:1}
    if [ $first_character = "-" ]; then
      cf_parameter_commands
    else
      record_name=${parameter_current}
      cf_ddns
    fi
  done
else
  # If no parameter been used it will use one above [record_name]
  cf_ddns
fi
debug_output_echo
exit $err_is_human
