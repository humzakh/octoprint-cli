#!/bin/bash
#####################
### SERVER CONFIG ###
#####################
server_url="http://$OCTO_IP_ADDRESS"
api_key="$OCTO_API_KEY"
#####################
### PRINTER CONFIG ##
#####################
max_bed_temp=140
max_hotend_temp=260
#####################
#####################
ProgramName=$(basename $0)

octo__help() {
  echo "Usage: $ProgramName [command] <option>"
  echo ""
  echo "Commands:"
  echo ""
  echo "    -h, --help"
  echo "         Print this help message."
  echo ""
  echo "    -c, --connect"
  echo "         Connect to printer via serial port."
  echo ""
  echo "    -d, --disconnect"
  echo "         Disconnect from printer."
  echo ""
  echo "    -C, --connection"
  echo "         Print connection status."
  echo ""
  echo "    -p, --psu <on | off | toggle | reboot | status>"
  echo "         Manage PSU state."
  echo "             Must have PSU Control plugin installed"
  echo "             & configured in your Octoprint instance."
  echo "               https://plugins.octoprint.org/plugins/psucontrol"
  echo "         <reboot>: Turns PSU off, waits 5 seconds, turns PSU on."
  echo ""
  echo "    -g, --gcode <'G-code Commands' | help>"
  echo "         Send G-code commands (semicolon separated) to printer."
  echo "         <help>: Display link to Marlin G-code documentation."
  echo ""
  echo "    -j, --job <start | cancel | resume | pause | status>"
  echo "         Manage job state."
  echo ""
  echo "    -F, --file <select | unselect>"
  echo "         Select/unselect file for printing from local storage."
  echo ""
  echo "    -b, --bed <off | [value in °C] | status>"
  echo "         Set heated bed temperature."
  echo ""
  echo "    -t, --tool, --hotend <off | [value in °C] | status>"
  echo "         Set tool/hotend temperature."
  echo ""
  echo "    -f, --fan <off | [0-100]% | [0-255]>"
  echo "         Set cooling fan speed."
  echo ""
}

post__request() {
  if [[ "$#" == 2 ]]; then
    response=$(curl --silent --show-error \
                    --header "Content-Type: application/json" \
                    --header "X-Api-Key: $api_key" \
                    --request POST \
                    --data "{\"command\":\"$1\"}" \
                    --url "$2" \
              2>&1)

    return_value=$?
    if [ $return_value -ne 0 ]; then
      echo ""
      echo "$response"
      exit $return_value
    fi

    if [ ! -z "$response" ]; then
      echo ""
      echo "$response" | jq
    fi
  fi
}

get__request() {
  curl --silent --show-error \
       --header "Content-Type: application/json" \
       --header "X-Api-Key: $api_key" \
       --request GET \
       --url "$1" \
      | jq
}

# arrowkey selection menu from: https://unix.stackexchange.com/a/415155
select_option() {
  # little helpers for terminal print control and key input
  ESC=$( printf "\033")
  cursor_blink_on()  { printf "$ESC[?25h"; }
  cursor_blink_off() { printf "$ESC[?25l"; }
  cursor_to()        { printf "$ESC[%s;${2:-1}H" "${1}"; }
  print_option()     { printf "   %s " "${1}"; }
  print_selected()   { printf "  $ESC[7m %s $ESC[27m" "${1}"; }
  get_cursor_row()   { IFS=';' read -sdR -p $'\E[6n' ROW COL; echo ${ROW#*[}; }
  key_input()        { read -s -n3 key 2>/dev/null >&2
                       if [[ $key = $ESC[A ]]; then echo up;    fi
                       if [[ $key = $ESC[B ]]; then echo down;  fi
                       if [[ $key = ""     ]]; then echo enter; fi; }

  # initially print empty new lines (scroll down if at bottom of screen)
  for opt; do printf "\n"; done

  # determine current screen position for overwriting the options
  local lastrow=`get_cursor_row`
  local startrow=$(($lastrow - $#))

  # ensure cursor and input echoing back on upon a ctrl+c during read -s
  trap "cursor_blink_on; stty echo; printf '\n'; exit" 2
  cursor_blink_off

  local selected=0
  while true; do
    # print options by overwriting the last lines
    local idx=0
    for opt; do
      cursor_to $(($startrow + $idx))
      if [ $idx -eq $selected ]; then
        print_selected "$opt"
      else
        print_option "$opt"
      fi
      ((idx++))
    done

    # user key control
    case `key_input` in
      enter) break;;
      up)    ((selected--));
             if [ $selected -lt 0 ]; then selected=$(($# - 1)); fi;;
      down)  ((selected++));
             if [ $selected -ge $# ]; then selected=0; fi;;
    esac
  done

  # cursor position back to normal
  cursor_to $lastrow
  printf "\n"
  cursor_blink_on

  return $selected
}
select_opt() {
  select_option "$@" 1>&2
  local result=$?
  echo $result
  return $result
}

octo__gcode() {
  local url="$server_url/api/printer/command"
  case $(tr '[:upper:]' '[:lower:]' <<< "$1") in
    "")
      echo "https://marlinfw.org/meta/gcode/"
      post__request "M300" "$url"
      ;;
    "help")
      echo "https://marlinfw.org/meta/gcode/" ;;
    *)
      local old_IFS="$IFS"
      while IFS=';\n\r' read -ra ADDR; do
        for addr in "${ADDR[@]}"; do
          local cmd=$(echo "$addr" | sed -e 's/^ *//' -e 's/ *$//' | tr '[:lower:]' '[:upper:]')
          echo -n "Sending \"$cmd\"..."
          post__request "$cmd" "$url"
          echo "done"
        done
      done <<< "$1"
      IFS="$old_IFS"
      ;;
  esac
}

octo__job() {
  local url="$server_url/api/job"
  case $(tr '[:upper:]' '[:lower:]' <<< "$1") in
    "start" | "cancel" | "restart")
      post__request $(tr '[:upper:]' '[:lower:]' <<< "$1") "$url" ;;
    "pause")
      local action=$(tr '[:upper:]' '[:lower:]' <<< "$2")
      case $action in
        "resume" | "toggle") ;;
        *)    action="pause" ;;
      esac
      post__request "pause\", \"action\":\"$action" "$url"
      ;;
    *);;
  esac
  >&2 echo "Retrieving job status..."
  get__request "$url"
}

octo__psu() {
  local url="$server_url/api/plugin/psucontrol"
  local cmd=""
  case $(echo "$1" | tr '[:upper:]' '[:lower:]') in
    "0" | "off")    cmd="turnPSUOff"; echo -n "Turning PSU off..." ;;
    "1" | "on")     cmd="turnPSUOn";  echo -n "Turning PSU on..." ;;
    "t" | "toggle") cmd="togglePSU";  echo -n "Toggling PSU..." ;;
    "r" | "reboot") cmd="reboot" ;;
    *)              cmd="getPSUState" ;;
  esac

  if [[ "$cmd" == "reboot" ]]; then
    echo -n "Turning PSU off..."
    post__request "turnPSUOff" "$url"
    echo "done"
    echo -n "Retrieving PSU status..."
    sleep 0.5
    post__request "getPSUState" "$url"
    sleep 5
    echo -n "Turning PSU on..."
    sleep 0.5
    post__request "turnPSUOn" "$url"
    echo "done"
    sleep 0.5
  elif [[ "$cmd" != "getPSUState" ]]; then
    post__request "$cmd" "$url"
    echo "done"
  fi
  >&2 echo -n "Retrieving PSU status..."
  sleep 0.5
  post__request "getPSUState" "$url"
}

octo__connection() {
  local url="$server_url/api/connection"
  case "$1" in
    "0")
      echo -n "Disconnecting from printer..."
      post__request "disconnect" "$url"
      echo "done"
      ;;
    "1")
      echo -n "Connecting to printer..."
      post__request "connect" "$url"
      echo "done"
      ;;
    *);;
  esac
  >&2 echo "Retrieving connection status..."
  sleep 0.5
  get__request "$url"
}

octo__file() {
  local url="$server_url/api/files"
  local json
  request_files() {
    echo "Requesting file list..."
    json=$(wget --quiet \
                --show-progress --progress=bar:force \
                --output-document - \
                --header="Content-Type: application/json" \
                --header="X-Api-Key: $api_key" \
                "$1" \
                | jq '.files |= sort_by(-.date) | .files[].name')
  }

  case "$(echo "$1" | tr '[:upper:]' '[:lower:]')" in
    "-u" | "u" | "unselect")
      if [[ "$(octo__connection 2>/dev/null | jq '.current.state')" == "\"Operational\"" ]]; then
        read -d '\r' origin file <<< "$(octo__job 2>/dev/null \
                                      | jq '.job.file.origin, .job.file.name' \
                                      | sed -e 's/^"//' -e 's/"$//' -e 's/ /%20/g')"
        if [[ "$origin" != "null" ]]; then
          echo -n "Unselecting: \"$(sed -e 's/%20/ /g' <<< "$file")\"..."
          sleep 0.5
          post__request "unselect" "$url/$origin/$file"
          if [ $? -ne 0 ]; then exit $?; fi
          if [[ "$(octo__job 2>/dev/null | jq '.job.file.name')" == "null" ]]; then
            echo "done"
          else
            echo ""
            echo "Error unselecting file."
            exit 2
          fi
        else
          echo "No file is currently selected."
        fi
      else
        echo "Error: Printer is not operational."
        exit 1
      fi
      ;;
    "-s" | "s" | "select")
      request_files "$url/local"
      if [ $? -ne 0 ]; then exit $?; fi

      if [[ ! $json ]]; then
        echo "No files returned."
        exit 2
      else
        echo ""
        echo "Select a file using up/down arrow keys, then press Enter:"
        echo ""
        local old_IFS="$IFS"
        IFS=$'\n', read -d '' -a filenames <<< "$json"
        IFS="$old_IFS"
        case `select_opt "${filenames[@]}"` in
          *)
            local file="${filenames[$?]}"
            echo -n "Selecting: $file..."
            sleep 0.5
            file="$(sed -e 's/^"//' -e 's/"$//' -e 's/ /%20/g' <<< "$file")"
            if [[ "$(octo__connection 2>/dev/null | jq '.current.state')" == "\"Operational\"" ]]; then
              post__request "select" "$url/local/$file"
              echo "done"
              sleep 0.5
              octo__job 2>/dev/null
            else
              echo ""
              echo "Error: Printer is not operational."
              exit 3
            fi
            ;;
        esac
      fi
      ;;
    "")
      echo "Error: Missing argument."
      echo "Usage:"
      echo "      $ProgramName --files <select | unselect>"
      exit 1
      ;;
    *)
      echo "Error: Invalid argument."
      echo "Usage:"
      echo "      $ProgramName --files <select | unselect>"
      exit 1
      ;;
  esac
}

octo__bed() {
  local url="$server_url/api/printer/bed"
  case "$1" in
    [0-9] | [0-9][0-9] | [0-9][0-9][0-9])
      if [ "$1" -le "$max_bed_temp" ]; then
        echo -n "Setting bed temperature to $1 °C..."
        octo__gcode "M140 S$1"
        echo "done"
      else
        echo "Error: Value too high. Max bed temperature: $max_bed_temp °C"
        exit 1
      fi
      ;;
    "off" | "cool" | "cooldown")
      echo -n "Setting bed temperature to 0 °C..."
      octo__gcode "M140 S0"
      echo "done"
      ;;
    "" | "status") ;;
    *)
      echo "Error: Invalid argument."
      echo "Usage:"
      echo "      $ProgramName --bed <off | [value in °C] | status>"
      exit 1
      ;;
  esac
  echo "Retrieving bed status..."
  sleep 0.5
  get__request "$url"
}

octo__tool() {
  local url="$server_url/api/printer/tool"
  case "$1" in
    [0-9] | [0-9][0-9] | [0-9][0-9][0-9])
      if [ "$1" -le "$max_hotend_temp" ]; then
        echo -n "Setting tool temperature to $1 °C..."
        octo__gcode "M104 S$1"
        echo "done"
      else
        echo "Error: Value too high. Max tool temperature: $max_hotend_temp °C"
        exit 1
      fi
      ;;
    "off" | "cool" | "cooldown")
      echo -n "Setting tool temperature to 0 °C..."
      octo__gcode "M104 S0"
      echo "done"
      ;;
    "" | "status") ;;
    *)
      echo "Error: Invalid argument."
      echo "Usage:"
      echo "      $ProgramName --tool <off | [value in °C] | status>"
      exit 1
      ;;
  esac
  echo "Retrieving tool status..."
  sleep 0.5
  get__request "$url"
}

octo__fan() {
  case "$1" in
    "")
      echo "Error: Missing argument."
      echo "Usage:"
      echo "      $ProgramName --fan <off | [0-100]% | [0-255]>"
      exit 1
      ;;
    [0-9] | [0-9][0-9] | [0-9][0-9][0-9])
      if [ "$1" -le 255 ]; then
        echo -n "Setting fan speed to $1..."
        sleep 0.5
        octo__gcode "M106 S$1"
        echo "done"
      else
        echo "Error: Value too high. Max fan speed: 255"
        exit 1
      fi
      ;;
    [0-9]% | [0-9][0-9]% | [0-9][0-9][0-9]%)
      local percentage=${1%\%}
      if [ "$percentage" -le 100 ] && [ "$percentage" -ge 0 ]; then
        local val=$(( 255*percentage/100 ))
        echo -n "Setting fan speed to $1..."
        sleep 0.5
        octo__gcode "M106 S$val"
        echo "done"
      else
        echo "Error: Invalid argument."
        echo "Usage:"
        echo "      $ProgramName --fan <[0-100]%>"
        exit 1
      fi
      ;;
    "off")
      echo -n "Setting fan speed to 0%..."
      sleep 0.5
      octo__gcode "M106 S0"
      echo "done"
      ;;
    *)
      echo "Error: Invalid argument."
      echo "Usage:"
      echo "      $ProgramName --fan <off | [0-100]% | [0-255]>"
      exit 1
      ;;
  esac
}

cmd="$1"
case "$cmd" in
  "" | "-h" | "--help")
    octo__help ;;
  "-g" | "--gcode")
    shift
    octo__gcode "$@"
    ;;
  "-j" | "--job")
    shift
    octo__job $@
    ;;
  "-p" | "--psu")
    shift
    octo__psu $@
    ;;
  "-c" | "--connect")
    shift
    octo__connection "1"
    ;;
  "-d" | "--disconnect")
    shift
    octo__connection "0"
    ;;
  "-C" | "--connection")
    shift
    octo__connection $@
    ;;
  "-F" | "--file")
    shift
    octo__file $@
    ;;
  "-b" | "--bed")
    shift
    octo__bed $@
    ;;
  "-t" | "--tool" | "--hotend")
    shift
    octo__tool $@
    ;;
  "-f" | "--fan")
    shift
    octo__fan $@
    ;;
  "cool" | "cooldown")
    octo__bed 0
    octo__tool 0
    octo__fan 0
    ;;
  *)
    echo "Error: invalid syntax or '$cmd' is not a known command." >&2
    echo "    Run '$ProgramName --help' for a list of known commands." >&2
    echo ""
    exit 1
    ;;
esac
