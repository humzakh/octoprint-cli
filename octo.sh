#!/bin/sh
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
  echo "Usage: $ProgramName [command] <option>\n"
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
  echo "    -b, --bed <off | 'value in °C' | status>"
  echo "         Set heated bed temperature."
  echo ""
  echo "    -t, --tool, --hotend <off | 'value in °C' | status>"
  echo "         Set tool/hotend temperature."
  echo ""
  echo "    -f, --fan <off | [0-100]% | [0-255]>"
  echo "         Set cooling fan speed."
  echo ""
}

post__request() {
  if [[ "$#" == 2 ]]; then
    curl --silent --show-error \
         --header "Content-Type: application/json" \
         --header "X-Api-Key: $api_key" \
         --request POST \
         --data "{\"command\":\"$1\"}" \
         --url "$2" \
        | jq
  fi
}

get__request() {
  echo ""
  curl --silent --show-error \
       --header "Content-Type: application/json" \
       --header "X-Api-Key: $api_key" \
       --request GET \
       --url "$1" \
      | jq
  echo ""
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
  case $(echo "$1" | tr '[:upper:]' '[:lower:]') in
    "")
      echo "https://marlinfw.org/meta/gcode/"
      post__request "M300" "$url"
      ;;
    "help")
      echo "https://marlinfw.org/meta/gcode/" ;;
    *)
      while IFS=';' read -ra ADDR; do
        for addr in "${ADDR[@]}"; do
          local cmd=$(echo "$addr" | tr '[:lower:]' '[:upper:]')
          post__request "$cmd" "$url"
        done
      done <<< "$1"
      ;;
  esac
}

octo__job() {
  local url="$server_url/api/job"
  case $(echo "$1" | tr '[:upper:]' '[:lower:]') in
    "start" | "cancel" | "restart")
      post__request $(echo "$1" | tr '[:upper:]' '[:lower:]') "$url" ;;
    "pause")
      local action=$(echo "$2" | tr '[:upper:]' '[:lower:]')
      case $action in
        "resume" | "toggle")
          ;;
        *)
          action="pause" ;;
      esac
      post__request "pause\", \"action\":\"$action" "$url"
      ;;
    *)
      ;;
  esac
  get__request "$url"
}

octo__psu() {
  local url="$server_url/api/plugin/psucontrol"
  local cmd=""
  case $(echo "$1" | tr '[:upper:]' '[:lower:]') in
    "0" | "off")    cmd="turnPSUOff" ;;
    "1" | "on")     cmd="turnPSUOn" ;;
    "t" | "toggle") cmd="togglePSU" ;;
    "r" | "reboot") cmd="reboot" ;;
    *)              cmd="getPSUState" ;;
  esac

  if [[ "$cmd" == "reboot" ]]; then
    post__request "turnPSUOff" "$url"
    post__request "getPSUState" "$url"
    sleep 5
    post__request "turnPSUOn" "$url"
  elif [[ "$cmd" != "getPSUState" ]]; then
    post__request "$cmd" "$url"
  fi

  post__request "getPSUState" "$url"
}

octo__connection() {
  local url="$server_url/api/connection"
  case "$1" in
    "0") post__request "disconnect" "$url" ;;
    "1") post__request "connect" "$url" ;;
    *)   ;;
  esac
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
    "-u" | "unselect")
      if [[ "$(octo__connection | jq '.current.state')" == "\"Operational\"" ]]; then
        local origin file
        read origin file <<< $(octo__job \
                               | jq '.job.file.origin, .job.file.name' \
                               | sed -e's/^"//' -e 's/"$//' -e 's/ /%20/g')
        if [[ "$origin" != "null" ]]; then
          post__request "unselect" "$url/$origin/$file"
          if [[ "$(octo__job | jq '.job.file.name')" == "null" ]]; then
            echo "Unselected: $file"
          else
            echo "Error unselecting file."
            exit 1
          fi
        else
          echo "No file is currently selected."
        fi
      else
        echo "Error: Printer not operational."
        exit 1
      fi
      ;;
    "-s" | "select")
      request_files "$url/local"

      if [[ ! $json ]]; then
        echo "No files returned."
        exit 1
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
            echo "Selected: $file"
            file="$(sed -e's/^"//' -e 's/"$//' -e 's/ /%20/g' <<< "$file")"
            if [[ "$(octo__connection | jq '.current.state')" == "\"Operational\"" ]]; then
              post__request "select" "$url/local/$file"
              sleep 0.5
              octo__job
            else
              echo "Error: Printer not operational."
              exit 1
            fi
            ;;
        esac
      fi
      ;;
    *)
      echo "Error: Invalid argument."
      exit 1
      ;;
  esac
}

octo__bed() {
  local url="$server_url/api/printer/bed"
  case "$1" in
    [0-9] | [0-9][0-9] | [0-9][0-9][0-9])
      if [ "$1" -le "$max_bed_temp" ]; then
        octo__gcode "M140 S$1"
        sleep 0.5
      else
        echo "Error: Value too high. Max bed temp: $max_bed_temp"
        exit 1
      fi
      ;;
    "off" | "cool" | "cooldown")
      octo__gcode "M140 S0"
      sleep 0.5
      ;;
    *);;
  esac
  get__request "$url"
}

octo__tool() {
  local url="$server_url/api/printer/tool"
  case "$1" in
    [0-9] | [0-9][0-9] | [0-9][0-9][0-9])
      if [ "$1" -le "$max_hotend_temp" ]; then
        octo__gcode "M104 S$1"
        sleep 0.5
      else
        echo "Error: Value too high. Max hotend temp: $max_hotend_temp"
        exit 1
      fi
      ;;
    "off" | "cool" | "cooldown")
      octo__gcode "M104 S0"
      sleep 0.5
      ;;
    *);;
  esac
  get__request "$url"
}

octo__fan() {
  case "$1" in
    "")
      echo "Error: Missing argument. <0-255> or <0-100>%"
      exit 1
      ;;
    [0-9] | [0-9][0-9] | [0-9][0-9][0-9])
      if [ "$1" -le 255 ]; then
        octo__gcode "M106 S$1"
      else
        echo "Error: Value too high. Max fan speed: 255"
        exit 1
      fi
      ;;
    [0-9]% | [0-9][0-9]% | [0-9][0-9][0-9]%)
      percentage=${1%\%}
      if [ "$percentage" -le 100 ] && [ "$percentage" -ge 0 ]; then
        val=$(( 255*percentage/100 ))
        octo__gcode "M106 S$val"
      else
        echo "Error: Invalid argument."
        exit 1
      fi
      ;;
    "off")
      octo__gcode "M106 S0" ;;
    *)
      echo "Error: Invalid argument."
      exit 1
      ;;
  esac
}

cmd="$1"
case $cmd in
  "" | "-h" | "--help")
    octo__help ;;
  "-g" | "--gcode")
    shift
    octo__gcode $@
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
