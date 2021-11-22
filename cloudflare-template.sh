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
config_file=""                                     # file that is config file

parameter_input=("$@")

cf_ddns_ip () {
  ###########################################
  ## Check if we have a public IP
  ###########################################
  ip=$(curl -s https://api.ipify.org || curl -s https://ipv4.icanhazip.com/)

  if [ "${ip}" == "" ]; then 
    logger -s "DDNS Updater: No public IP found"
    debug_output+="$logger_output\n"
    logger -s "$logger_output"
    #no point going on if can not get ip
    exit_code 1
  fi
}

cf_ddns_authheader (){
  ###########################################
  ## Check and set the proper auth header
  ###########################################
  if [ "${auth_method}" == "global" ]; then
    auth_header="X-Auth-Key:"
  else
    auth_header="Authorization: Bearer"
  fi
 }

cf_ddns_seeka () {
  ###########################################
  ## Seek for the A record
  ###########################################

  logger "DDNS Updater: Check Initiated"
  debug_output+="$logger_output\n"
  record=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$zone_identifier/dns_records?type=A&name=$record_name" \
                        -H "X-Auth-Email: $auth_email" \
                        -H "$auth_header $auth_key" \
                        -H "Content-Type: application/json")
  debug_output+="cf_ddns_seeka : $record\n"
}

cf_ddns_checka () {
  ###########################################
  ## Check if the domain has an A record
  ###########################################
  if [[ $record == *"\"count\":0"* ]]; then
    logger_output="DDNS Updater: Record does not exist, perhaps create one first? (${ip} for ${record_name})"
      debug_output+="$logger_output\n"
      logger -s "$logger_output"
      cf_nonexistsrecord=0
      exit_code 1
  else
    cf_nonexistsrecord=1
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
      debug_output+="$logger_output\n"
      logger -s "$logger_output"
      exit_code 0
  fi
}

cf_ddns_set_identifier () {
  ##########################################
  ## Set the record identifier from result
  ###########################################
  record_identifier=$(echo "$record" | sed -E 's/.*"id":"(\w+)".*/\1/')
  debug_output+="cf_ddns_set_identifier : $record_identifier\n"
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
  debug_output+="cf_ddns_update : $update\n"
}

cf_ddns_status () {
  ###########################################
  ## Report the status
  ###########################################
  case "$update" in
  *"\"success\":false"*)
    logger_output="DDNS Updater: $ip $record_name DDNS failed for $record_identifier ($ip). DUMPING RESULTS:\n$update"
    debug_output+="$logger_output\n"
    logger -s "$logger_output"
    if [[ $slackuri != "" ]]; then
      curl -L -X POST $slackuri \
      --data-raw '{
        "channel": "'$slackchannel'",
        "text" : "'"$slacksitename"' DDNS Update Failed: '$record_name': '$record_identifier' ('$ip')."
      }'
    fi
    exit_code 1;;
  *)
    logger_output="DDNS Updater: $ip $record_name DDNS updated."
    debug_output+="$logger_output\n"
    logger "$logger_output"
    if [[ $slackuri != "" ]]; then
      curl -L -X POST $slackuri \
      --data-raw '{
        "channel": "'$slackchannel'",
        "text" : "'"$slacksitename"' Updated: '$record_name''"'"'s'""' new IP Address is '$ip'"
      }'
    fi
    exit_code 0;;
  esac
}

cf_ddns() {
  if [ ${#ip} -eq 0 ]; then
  #Only worth getting current IP address with first domain
    cf_ddns_ip
  fi

  cf_ddns_authheader
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

debug_output_echo () {
  if [ -n "$debug_mode_active" ]; then
    if [ "$debug_mode_active" -eq 1 ]; then
      echo -e "$debug_output"
    fi
  fi
}

exit_code () {
  excode="$1"
  if [ -z "$top_exit_code" ]; then
    top_exit_code=-999
  fi
  if [ $top_exit_code -lt "$excode" ]; then
    top_exit_code=$excode
  fi

  if [ $tolerant_is_set -eq 1 ]; then
  # Only when tolerent mode is active, it will not stop for error
    logger_output="DDNS Updater: in tolerant mode - exit [$excode]"
    debug_output+="$logger_output\n"
    logger "$logger_output"
  else
  #If strict mode it will stop instantly on error
    debug_output_echo
    exit "$excode"
  fi
}



cf_counting_sheep () { 
  datestart=$(date +%Y/%m/%d\ %H:%M:%S)
  dateend=$(date --date="+$parameter_value seconds" +"%Y-%m-%d %H:%M:%S")
  logger_output="DDNS Updater: counting sheep ($parameter_value) $datestart : $dateend"
  debug_output+="$logger_output\n"
  logger -s "$logger_output"
  sleep "$parameter_value"
}

cf_help () {
  echo "# crontab"
  echo "*/5 * * * * /bin/bash /home/user/cloudflare-ddns-updater/cloudflare-init.sh"
  echo '*/5 * * * * /bin/bash /home/user/cloudflare-ddns-updater/cloudflare-init.sh -tolerant mydomain.com example.com www.example.com x1.example.com'
  echo '*/5 * * * * /bin/bash /home/user/cloudflare-ddns-updater/cloudflare-init.sh -tolerant mydomain.com -sleep=10 example.com -proxy=false www.example.com -auth_ttl=10 x1.example.com'
  echo "Add in -tolerant option that get continue if when reason to exit, this should be first parameter"
  echo "-sleep=X will make it sleep for X seconds before doing proceeding domains"
  echo "-rsleep=X will random range from 0 to X seconds"
  echo "-auth_email=X it for this will change it for proceeding domains"
  echo "-auth_method=X it for this will change it for proceeding domains"
  echo "-auth_key=X it for this will change it for proceeding domains"
  echo "-auth_identifier=X it for this will change it for proceeding domains"
  echo "-auth_ttl=X it for this will change it for proceeding domains"
  echo "-auth_proxy=X it for this will change it for proceeding domains"
  echo "-purge will purge current setting for cloudflare"
}

cf_tolerant () {
  tolerant_is_set=1
  logger_output="DDNS Updater: Been set as being tolerant"
  debug_output+="$logger_output\n"
  logger "$logger_output"
}

cf_rsleep () {
  logger_output="DDNS Updater: rsleep range ($parameter_value) : "
  parameter_temp=$(( $parameter_value+1 ))
  parameter_value=$(( $RANDOM % $parameter_temp ))
  logger_output+="($parameter_value)"
  debug_output+="$logger_output\n"
  logger "$logger_output"
  cf_counting_sheep
}

cf_auth_email () {
  logger_output="DDNS Updater: Changed [auth_email]"
  debug_output+="$logger_output ($parameter_value)\n"
  logger "$logger_output"
  auth_email=$parameter_value
}

cf_auth_method () {
  logger_output="DDNS Updater: Changed [auth_email]"
  debug_output+="$logger_output ($parameter_value)\n"
  logger "$logger_output"
  auth_method=$parameter_value
}

cf_auth_key () {
  logger_output="DDNS Updater: Change [auth_key]"
  debug_ouput+="$logger_output ($parameter_value)\n"
  logger "$logger_output"
  auth_key=$parameter_value
}

cf_zone_identifier () {
  logger_output="DDNS Updater: Change [zone_identifier]"
  debug_ouput+="$logger_output ($parameter_value)\n"
  logger "$logger_output"
  zone_identifier=$parameter_value
}

cf_ttl () {
  logger_output="DDNS Updater: Change [ttl]"
  debug_ouput+="$logger_output ($parameter_value)\n"
  logger "$logger_output"
  ttl=$parameter_value
}

cf_proxy () {
  logger_output="DDNS Updater: Changed [proxy]"
  if [ $parameter_value = "true" ] || [ $parameter_value = "false" ]; then
    logger_output+=" ($parameter_value)"
    proxy=$parameter_value
    logger "$logger_output"
  else
    logger_output+=" ($parameter_value) is invalied option"
    logger -s "$logger_output"
  fi
  debug_output+="$logger_output\n"
}

cf_record_name () {
  record_name=$parameter_value
  cf_err_human
  if [ "$err_is_human" -eq 0 ]; then
    cf_ddns
  fi
  #TODO **************************************************************************************************************************
}

cf_ipset () {
  ip=$parameter_value
  logger_output="DDNS Updater: IP been set to $ip"
  logger "$logger_output"
  debug_ouput+="$logger_output\n"
}

cf_ipcheck () {
  ip=""
  logger_output="DDNS Updater: IP been set to do a recheck"
  logger "$logger_output"
  debug_ouput+="$logger_output\n"
}

cf_entry_point () {
  logger_output="DDNS Updater: [entrypoint] ($parameter_value)"
  logger "$logger_output"
  debug_ouput+="$logger_output\n"
}

cf_remark_statment () {
  debug_output+="REMark: $parameter_value\n"
}

cf_parameter_commands () {

  parameter_temp="${1:1}"
  parameter_command=${parameter_temp%=*}
  parameter_value=${parameter_temp##*=}

  case $parameter_command in
    "debug")
      #debug_mode_active=1
      :
      ;;
    "help")
      cf_help
      ;;
    "tolerant")
      #cf_tolerant
      :
      ;;
    "sleep")
      cf_counting_sheep
      ;;
    "rsleep")
      cf_rsleep
      ;;
    "auth_email")
      cf_auth_email
      ;;
    "auth_method")
      cf_auth_method
      ;;
    "auth_key")
      cf_auth_key
      ;;
    "zone_identifier")
      cf_zone_identifier
      ;;
    "ttl")
      cf_ttl
      ;;
    "proxy")
      cf_proxy
      ;;
    "record_name")
      cf_record_name
      ;;
    "ipset")
      cf_ipset
      ;;
    "ipcheck")
      cf_ipcheck
      ;;
    "entrypoint")
      cf_entry_point
      ;;
    "purge")
      cf_to_null
      ;;
    
    "#")
      cf_remark_statment
      ;;
    "config_file")
      :
      ;;
    *)
      logger_output="DDNS Updater: invalid parameter option been defined [${parameter_temp}]"
      debug_output+="$logger_output\n"
      logger -s "$logger_output"
      ;;
  esac
}

cf_err_human () {
  err_is_human=0

  if [ ${#auth_email} -eq 0 ]; then
    err_is_human=1
    logger_output="DDNS Updater: ERROR [auth_email] record not been defined"
    logger -s "$logger_output"
  fi

  if [ ${#auth_method} -eq 0 ]; then
    err_is_human=1
    logger_output='DDNS Updater: ERROR [auth_method] setting has not been defined'
    logger -s "$logger_output"
  else
    if [ $auth_method != "token" ] && [ $auth_method != "global" ]; then
      err_is_human=1
      logger_output='DDNS Updater: ERROR [auth_method] is invaled it has to be defined "token" "global" defined'
      logger -s "$logger_output"
    fi
  fi

  if [ ${#auth_key} -eq 0 ]; then
    err_is_human=1
    logger_output="DDNS Updater: ERROR [auth_key] record not been defined"
    logger -s "$logger_output"
  fi

  if [ ${#zone_identifier} -eq 0 ]; then
    err_is_human=1
    logger_output="DDNS Updater: ERROR [zone_identifier] record has not been defined"
    logger -s "$logger_output"
  fi

  if [ ${#record_name} -eq 0 ]; then
    err_is_human=1
    logger_output="DDNS Updater: ERROR [record_name] record has not been defined"
    logger -s "$logger_output"
  fi

   if [ ${#ttl} -eq 0 ]; then
    err_is_human=1
    logger_output="DDNS Updater: ERROR [ttl] record has not been defined"
    logger -s "$logger_output"
  fi

  if [ ${#proxy} -eq 0 ]; then
    err_is_human=1
    logger_output='DDNS Updater: ERROR [proxy] setting has not been defined'
    logger -s "$logger_output"
  else
    if [ $proxy != "true" ] && [ $proxy != "false" ]; then
      err_is_human=1
      logger_output='DDNS Updater: ERROR [proxy] is invaled it has to be defined "true" "false" defined'
      logger -s "$logger_output"
    fi
  fi
    
  if [ ${#record_name} -eq 0 ]; then 
    err_is_human=1
    logger_output="DDNS Updater: ERROR [record_name] record not has been defined"
    logger -s "$logger_output"
  fi

  if [ -z "$tolerant_is_set" ]; then
    # if tolerant_is_set has not been set up it will be strict
    tolerant_is_set=0
  fi

  if [ $tolerant_is_set -lt 0 ] || [ $tolerant_is_set -gt 1 ]; then
    err_is_human=1
    logger_output="DDNS Updater: ERROR [tolerant_is_set] can only by 0 or 1"
    logger -s "$logger_output"
  fi

  if [ $err_is_human -eq 1 ]; then
    #It is done if there is error detected above
    exit_code 1
  fi
}

cf_to_null () {
  auth_email=""
  auth_method=""
  auth_key=""
  zone_identifier=""
  record_name=""
  ttl=""
  proxy=""
  #ip=""
}

cf_setting_internal () {
  debug_output_local="cf_setting_internal:"
  cf_setting_internal_array=('-entrypoint=_settinginternal')

  if [[ -z $auth_email ]]; then
    debug_output+="$debug_output_local undefined [auth_email]\n"
  else
    cf_setting_internal_array+=("-auth_email=$auth_email")
  fi
  if [[ -z $auth_method ]]; then
    debug_output+="$debug_output_local undefined [auth_method]\n"
  else
    cf_setting_internal_array+=("-auth_method=$auth_method")
  fi
  if [[ -z $auth_key ]]; then
    debug_output+="$debug_output_local undefined [auth_key]\n"
  else
    cf_setting_internal_array+=("-auth_key=${auth_key}")
  fi
  if [[ -z $zone_identifier ]]; then
    debug_output+="$debug_output_local undefined [zone_identifier]\n"
  else
    cf_setting_internal_array+=("-zone_identifier=${zone_identifier}")
  fi
  if [[ -z $ttl ]]; then
    debug_output+="$debug_output_local undefined [ttl]\n"
  else
    cf_setting_internal_array+=("-ttl=${ttl}")
  fi
  if [[ -z $proxy ]]; then
    debug_output+="$debug_output_local undefined [proxy]\n"
  else
    cf_setting_internal_array+=("-proxy=${proxy}")
  fi
  if [[ -z $slacksitename ]]; then
    debug_output+="$debug_output_local undefined [slacksitename]\n"
  else
    cf_setting_internal_array+=("-slacksitename=${slacksitename}")
  fi
  if [[ -z $slackchannel ]]; then
    debug_output+="$debug_output_local undefined [slackchannel]\n"
  else
    cf_setting_internal_array+=("-slackchannel=${slackchannel}")
  fi
  if [[ -z $slackuri ]]; then
    debug_output+="$debug_output_local undefined [slackuri]\n"
  else
    cf_setting_internal_array+=("-slackuri=${slackuri}")
  fi
  if [[ -z $config_file ]]; then
    debug_output+="$debug_output_local undefined [config_file]\n"
  else
    cf_setting_internal_array+=("-config_file=${config_file}")
  fi

  ## This has to called last as it do process of conatcting CF and the seting have to be already set
  if [[ -z $record_name ]]; then
    debug_output+="$debug_output_local undefined [record_name]\n"
  else
    cf_setting_internal_array+=("-record_name=${record_name}")
  fi

  for (( item=0; item < ${#cf_setting_internal_array[@]}; item++ )); do
    debug_output+="$debug_output_local declared ${cf_setting_internal_array[item]}\n"
  done
}

cf_setting_parameter () {
  debug_output_local="cf_setting_parameter:"
  argument_total=${#parameter_input[@]}
  
  if [ "$argument_total" -gt 0 ] ; then
    cf_setting_parameter_array=('-entrypoint=_settingparameter')
    for (( argument_depth=0 ; argument_depth < argument_total ; argument_depth++ )); do
      parameter_current=${parameter_input[argument_depth]}
      first_character=${parameter_current:0:1}
      # $'\055') # Hyphen -
      if [[ $first_character = $'\055' ]]; then
        retain_setting_to_check="$parameter_current"
        retain_setting 
        activate_instantly_settings
        cf_setting_parameter_array+=("${retain_setting_output}")
      else
        cf_setting_parameter_array+=('-record_name='"${parameter_current}")
      fi
    done
  fi

  for (( item=0; item < ${#cf_setting_parameter_array[@]}; item++ )); do
    debug_output+="$debug_output_local declared ${cf_setting_parameter_array[item]}\n"
  done

}

cf_setting_file () {
#i: config_file
#i: line_to_check
#i: string_exit
#i: string_filename
#io: string_exit
#io: string_y_pos
#io: string_x_pos
#o: string_character

  string_y_pos=0
  debug_output_local="cf_setting_file:"
  if [ -f $config_file ] && [ $config_file ]; then
    cf_setting_file_array=('-entrypoint=_settingfile')
    while IFS= read -r string_text
    do
      ((string_y_pos++))
      string_reset_whitespace
      # It will process only the line set as in $line_to_check
      # It will process everyline if $line_to_check == 0 or null
      if [[ $line_to_check == "$string_y_pos" ]] || [[ $line_to_check == 0 ]] || [[ -z $line_to_check ]]; then
        until (( $string_exit )); do
          string_character=${string_text:string_x_pos:1}
          string_check_whitspace
          ((string_x_pos++))
          string_length_check
        done
        if [[ $string_removed_whitespace ]]; then
          first_character=${string_removed_whitespace:0:1}
          # $'\055') # Hyphen -
          if [[ $first_character = $'\055' ]]; then
            retain_setting_to_check="$string_removed_whitespace"
            retain_setting 
            activate_instantly_settings
          else
            retain_setting_output=("-record_name=${string_removed_whitespace}")
          fi
          cf_setting_file_array+=("${retain_setting_output}")
        fi
     fi
    done < "$config_file"
  else
    if [[ $config_file ]]; then
      logger_output="DDNS Updater: ${debug_output_local}file not found [${config_file}]"
      debug_output+="$logger_output\n"
      logger -s "$logger_output"
    fi
  fi

  for (( item=0; item < ${#cf_setting_file_array[@]}; item++ )); do
    debug_output+="$debug_output_local declared ${cf_setting_file_array[item]}\n"
  done
}

string_reset_whitespace () {
#i: string_text
#o: string_exit
#o: string_x_pos
#o: within_quatation_mark
#o: string_remove_whitspace
#o: string_length
  
  string_exit=0
  string_x_pos=0
  string_where_equal_sign=0
  within_quatation_mark=0
  string_removed_whitespace=""
  string_length=${#string_text}
}

string_check_whitspace () {
#i: string_character
#i: string_x_pos
#i: string_y_pos
#io: string_removed_whitespace
#io: within_quatation_mark
#io: string_where_equal_sign

  # \011 = Tab (Tab vertical) || \040 = Space
  if [[ $string_character == $'\011' ]] || [[ $string_character == $'\040' ]]; then
    if (( $within_quatation_mark )); then
      string_removed_whitespace+=$string_character
    fi
  else
    string_non_whitespace
  fi
}

string_length_check () {
#i: string_length
#i: string_x_pos
#o: string_exit
  if [ "$string_length" -eq $string_x_pos ]; then
    string_exit=1
  fi
  # $string_length = 0 is for line that have nothing
  if [ "$string_length" -eq 0 ]; then
    string_exit=1
  fi
}

string_non_whitespace (){
  # \042 Quatation mark
  if [[ $string_character == $'\042' ]]; then
    within_quatation_mark=$(( ! $within_quatation_mark ))
  else 
    #doing after else will remove remove Quatation Mark, otherwise if want it remove else place after fi
    string_removed_whitespace+=$string_character
  fi
  
  # \075 Equal Sign
  # it only valied if not already been set and quatation mark is false
  if [[ $string_character == $'\075' ]] && (( ! $within_quatation_mark )); then
    if [[ $string_where_equal_sign == 0 ]]; then
      string_where_equal_sign=${#string_removed_whitespace}
    fi
  fi
}


retain_setting () {
  # The first time it declared it vaild, anthing else is not vaild.
  retain_setting_output=$retain_setting_to_check
  if [ "${retain_setting_to_check:0:13}" == "-config_file=" ]; then
    if [ $config_file ]; then
      logger_output="DDNS Updater: ${debug_output_local} [-config_file] already defened as [${config_file}] not changed to [${retain_setting_to_check:13}]"
      debug_output+="$logger_output\n"
      logger -s "$logger_output"
      # This is done so file name is rem out
      retain_setting_output="-#=$retain_setting_to_check"
    else
      config_file=${retain_setting_to_check:13}
      retain_setting_output=$config_file
    fi
  fi

  
}

activate_instantly_settings () {
  if [ "${retain_setting_to_check:0:6}" == "-debug" ]; then
    debug_mode_active=1
  fi                   

  if [ "${retain_setting_to_check:0:9}" == "-tolerant" ]; then
    cf_tolerant
  fi
}

cf_exec () {  
  for (( item=0; item < ${#cf_setting_internal_array[@]}; item++ )); do
    cf_parameter_commands "${cf_setting_internal_array[item]}"
  done

  for (( item=0; item < ${#cf_setting_parameter_array[@]}; item++ )); do
    cf_parameter_commands "${cf_setting_parameter_array[item]}"
  done

  for (( item=0; item < ${#cf_setting_file_array[@]}; item++ )); do
    cf_parameter_commands "${cf_setting_file_array[item]}"
  done
}

cf_kickstart () {
  cf_setting_internal
  cf_setting_parameter
  cf_setting_file 
  cf_to_null
  cf_exec
  debug_output_echo
}



cf_kickstart


#echo -e "$debug_output"

#echo "intrenal :${cf_setting_internal_array[*]}"
#echo "paramter :${cf_setting_parameter_array[*]}"
#echo "file :${cf_setting_file_array[*]}"
#exit

