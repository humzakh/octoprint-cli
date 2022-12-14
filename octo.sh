#!/bin/bash
ProgramName="$(basename $0)"
ProgramDir="$(cd $(dirname $0) && pwd)"

if test -f ${ProgramDir}/octo.cfg; then
  . ${ProgramDir}/octo.cfg
else
  echo "Configuration file \"octo.cfg\" not found!" >&2
  echo -e "Create \"\033[1;33mocto.cfg\033[0m\" in \"\033[1;33m$ProgramDir\033[0m\""
  echo "Download/copy the template from: https://github.com/humzakh/octoprint-cli/blob/master/octo.cfg"
  exit 8
fi

function octo__help() {
  echo "Usage: $ProgramName [command] <option>"
  echo ""
  echo "Commands:"
  echo ""
  echo "    -h, --help"
  echo "         Display this help message."
  echo ""
  echo "    -c, --connect"
  echo "         Connect to printer via serial port."
  echo ""
  echo "    -d, --disconnect"
  echo "         Disconnect from printer."
  echo ""
  echo "    -C, --connection"
  echo "         Display connection status."
  echo ""
  echo "    -p, --psu <on | off | toggle | reboot | status>"
  echo "         Manage PSU state."
  echo "             Must have PSU Control plugin installed"
  echo "             & configured in your Octoprint instance."
  echo "               https://plugins.octoprint.org/plugins/psucontrol"
  echo "         Each of these PSU options can be sent as their own commands."
  echo "             e.g. --on, --off, --reboot, etc."
  echo ""
  echo "    -g, --gcode <'G-code Commands' | help>"
  echo "         Send G-code commands (semicolon separated) to printer."
  echo "         <help>: Display link to Marlin G-code documentation."
  echo ""
  echo "    -s, --select"
  echo "         Select a file for printing from local storage."
  echo ""
  echo "    -u, --unselect"
  echo "         Unselect currently selected file."
  echo ""
  echo "    -j, --job"
  echo "         View current job status."
  echo ""
  echo "    -S, --start"
  echo "         Start print job."
  echo ""
  echo "    -C, --cancel"
  echo "         Abort current print job."
  echo ""
  echo "    -P, --pause"
  echo "         Pause current print job."
  echo ""
  echo "    -R, --resume"
  echo "         Resume paused print job."
  echo ""
  echo "    -b, --bed <off | [value in ??C] | status>"
  echo "         Set heated bed temperature."
  echo ""
  echo "    -t, --tool, --hotend <off | [value in ??C] | status>"
  echo "         Set tool/hotend temperature."
  echo ""
  echo "    -f, --fan <off | [0-100]% | [0-255]>"
  echo "         Set cooling fan speed."
  echo ""
  echo "    -ph, --preheat <'profile name' | add | remove | list>"
  echo "         Preheat bed/tool using values in the given preheat profile."
  echo ""
}

function post__request() {
  if [[ $# == 2 ]]; then
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
    elif [ ! -z "$response" ]; then
      echo ""
      echo "$response" | jq
    fi
  else
    echo "Error: post__request invalid arguments." >&2
    exit 9
  fi
}

function get__request() {
  curl --silent --show-error \
       --header "Content-Type: application/json" \
       --header "X-Api-Key: $api_key" \
       --request GET \
       --url "$1" \
      | jq
}

# arrowkey selection menu from: https://unix.stackexchange.com/a/415155
function select_option() {
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
function select_opt() {
  select_option "$@" 1>&2
  local result=$?
  echo $result
  return $result
}

function octo__sleep() {
  if ! [[ "$1" =~ ^[0-9]+$ ]]; then
    echo "Error: Invalid input." >&2
    exit 1
  fi

  secs=$(($1 * 60))
  while [ $secs -gt 0 ]; do
    printf "\015\033[2K%02d:%02d:%02d" $((secs/3600)) $(((secs/60)%60)) $((secs%60))
    sleep 1
    : $((secs--))
  done
  echo -ne "\033[0K\r"
}

function octo__gcode() {
  local url="$server_url/api/printer/command"
  case $(tr '[:upper:]' '[:lower:]' <<< "$1") in
    "")
      echo "https://marlinfw.org/meta/gcode/"
      post__request "M300" "$url"
      ;;
    "help")
      echo "https://marlinfw.org/meta/gcode/" ;;
    *)
      show_cmd=true
      if [[ $# == 2 ]]; then
        case "$1" in
          "--silent")
            show_cmd=false
            shift
            ;;
          *);;
        esac
      fi

      local old_IFS="$IFS"
      while IFS=';\n\r' read -ra ADDR; do
        for addr in "${ADDR[@]}"; do
          local cmd=$(echo "$addr" | sed -e 's/^ *//' -e 's/ *$//' | tr '[:lower:]' '[:upper:]')
          if [ "$show_cmd" = true ]; then echo -n "Sending \"$cmd\"..."; fi
          local response="$(post__request "$cmd" "$url")"
          if [[ "$(jq '.error' <<< "$response")" == "\"Printer is not operational\"" ]]; then
            echo ""
            jq <<< "$response"
            exit 4
          fi
          if [ "$show_cmd" = true ]; then echo "done"; fi
        done
      done <<< "$1"
      IFS="$old_IFS"
      ;;
  esac
}

function octo__job() {
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
    "time")
      local response="$(get__request "$url")"
      if [[ "$(jq '.state' <<< "$response")" == "\"Printing\"" ]]; then
        printTime="$(jq '.progress.printTime' <<< "$response")"
        printTimeLeft="$(jq '.progress.printTimeLeft' <<< "$response")"
        printTimeLeftOrigin="$(jq '.progress.printTimeLeftOrigin' <<< "$response")"

        printf "\033[31mPrint Time:        %02d:%02d:%02d\012" \
          $((printTime/3600)) $(((printTime/60)%60)) $((printTime%60))
        printf "\033[32mPrint Time Left:   %02d:%02d:%02d\012" \
          $((printTimeLeft/3600)) $(((printTimeLeft/60)%60)) $((printTimeLeft%60))
        printf "\033[34mPrint Time Origin: $printTimeLeftOrigin\033[0m\012"
      else echo "Printer is not printing."
      fi
      exit 0
      ;;
    *);;
  esac
  >&2 echo "Retrieving job status..."
  get__request "$url"
}

function octo__psu() {
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
    sleep 0.5
  fi
  >&2 echo -n "Retrieving PSU status..."
  sleep 0.5
  post__request "getPSUState" "$url"
}

function octo__connection() {
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

function octo__file() {
  local url="$server_url/api/files"
  local json
  function request_files() {
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
            echo "Error unselecting file." >&2
            exit 2
          fi
        else
          echo "No file is currently selected."
        fi
      else
        echo "Error: Printer is not operational." >&2
        exit 1
      fi
      ;;
    "-s" | "select")
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
              echo "Error: Printer is not operational." >&2
              exit 3
            fi
            ;;
        esac
      fi
      ;;
    "")
      echo "Error: Missing argument." >&2
      echo "Usage:"
      echo "      $ProgramName --files <select | unselect>"
      exit 1
      ;;
    *)
      echo "Error: Invalid argument." >&2
      echo "Usage:"
      echo "      $ProgramName --files <select | unselect>"
      exit 1
      ;;
  esac
}

function octo__bed() {
  local url="$server_url/api/printer/bed"
  case "$1" in
    [0-9] | [0-9][0-9] | [0-9][0-9][0-9])
      if [ "$1" -le "$max_bed_temp" ]; then
        echo -n "Setting bed temperature to $1 ??C..."
        octo__gcode --silent "M140 S$1"
        echo "done"
      else
        echo "Error: Value too high. Max bed temperature: $max_bed_temp ??C"
        exit 1
      fi
      ;;
    "off" | "cool" | "cooldown")
      echo -n "Setting bed temperature to 0 ??C..."
      octo__gcode --silent "M140 S0"
      echo "done"
      ;;
    "" | "status") ;;
    *)
      echo "Error: Invalid argument." >&2
      echo "Usage:"
      echo "      $ProgramName --bed <off | [value in ??C] | status>"
      exit 1
      ;;
  esac
  sleep 0.5
  echo "Retrieving bed status..."
  sleep 0.5
  get__request "$url"
}

function octo__tool() {
  local url="$server_url/api/printer/tool"
  case "$1" in
    [0-9] | [0-9][0-9] | [0-9][0-9][0-9])
      if [ "$1" -le "$max_tool_temp" ]; then
        echo -n "Setting tool temperature to $1 ??C..."
        octo__gcode --silent "M104 S$1"
        echo "done"
      else
        echo "Error: Value too high. Max tool temperature: $max_tool_temp ??C" >&2
        exit 1
      fi
      ;;
    "off" | "cool" | "cooldown")
      echo -n "Setting tool temperature to 0 ??C..."
      octo__gcode --silent "M104 S0"
      echo "done"
      ;;
    "" | "status") ;;
    *)
      echo "Error: Invalid argument." >&2
      echo "Usage:"
      echo "      $ProgramName --tool <off | [value in ??C] | status>"
      exit 1
      ;;
  esac
  sleep 0.5
  echo "Retrieving tool status..."
  sleep 0.5
  get__request "$url"
}

function octo__fan() {
  case "$1" in
    "")
      echo "Error: Missing argument." >&2
      echo "Usage:"
      echo "      $ProgramName --fan <off | [0-100]% | [0-255]>"
      exit 1
      ;;
    [0-9] | [0-9][0-9] | [0-9][0-9][0-9])
      if [ "$1" -le 255 ]; then
        echo -n "Setting fan speed to $1..."
        sleep 0.5
        octo__gcode --silent "M106 S$1"
        echo "done"
      else
        echo "Error: Value too high. Max fan speed: 255" >&2
        exit 1
      fi
      ;;
    [0-9]% | [0-9][0-9]% | [0-9][0-9][0-9]%)
      local percentage=${1%\%}
      if [ "$percentage" -le 100 ] && [ "$percentage" -ge 0 ]; then
        local val=$(( 255*percentage/100 ))
        echo -n "Setting fan speed to $1..."
        sleep 0.5
        octo__gcode --silent "M106 S$val"
        echo "done"
      else
        echo "Error: Invalid argument." >&2
        echo "Usage:"
        echo "      $ProgramName --fan <[0-100]%>"
        exit 1
      fi
      ;;
    "off")
      echo -n "Setting fan speed to 0%..."
      sleep 0.5
      octo__gcode "__octo__" "M106 S0"
      echo "done"
      ;;
    *)
      echo "Error: Invalid argument." >&2
      echo "Usage:"
      echo "      $ProgramName --fan <off | [0-100]% | [0-255]>"
      exit 1
      ;;
  esac
}

function octo__preheat() {
  ph_file="$ProgramDir/octo_preheat_profiles.json"

  function create_ph_file() {
    if [ ! -f $ph_file ]; then
      echo -e "File \"$ProgramDir/\033[33mocto_preheat_profiles.json\033[0m\" not found." >&2
      while true; do
        read -p "Create file? [y/N]: " -n 1 yn
        echo ""
        case $yn in
          [yY])
            echo -n "Creating \"$ph_file\"..."
            echo '{ "profiles": {} }' > $ph_file
            echo "done"
            echo ""
            echo "Add a preheat profile with the following command:"
            echo "      $ProgramName -ph add"
            echo ""
            exit 0
            ;;
          [nN]) exit 0;;
          *) continue ;;
        esac
      done
    fi
  }

  function add_profile() {
    echo "Creating preheat profile..."

    while true; do
      read -p "Enter preheat profile name: " ph_name
      case "$ph_name" in
        *[[:space:]]*)
          echo "Error: Invalid input. Profile name cannot contain spaces." >&2
          continue
          ;;
        "add" | "list" | "remove")
          echo "Error: \"$ph_name\" is reserved and cannot be used as a profile name." >&2
          continue
          ;;
        "") ;;
        *)
          if [ $(jq ".profiles | has(\"$ph_name\")" $ph_file ) == true ]; then
            echo "Error: Profile \"$ph_name\" already exists." >&2
            exit 1
          else break
          fi
          ;;
      esac
    done

    while true; do
      read -p "Enter bed preheat temperature: " ph_bed

      if ! [[ "$ph_bed" =~ ^[0-9]+$ ]]; then
        echo "Error: Invalid input." >&2
        continue
      fi

      if [ "$ph_bed" -le "$max_bed_temp" ]; then break
      else
        echo "Error: Value too high. Max bed temperature: $max_bed_temp ??C" >&2
        continue
      fi
    done

    while true; do
    read -p "Enter tool preheat temperature: " ph_tool

      if ! [[ "$ph_tool" =~ ^[0-9]+$ ]]; then
        echo "Error: Invalid input." >&2
        continue
      fi

      if [ "$ph_tool" -le "$max_tool_temp" ]; then break
      else
        echo "Error: Value too high. Max tool temperature: $max_tool_temp ??C" >&2
        continue
      fi
    done

    ph_profile=$(jq -n \
                    --arg name "$ph_name" \
                    --argjson bed "$ph_bed" \
                    --argjson tool "$ph_tool" \
                    '{($name):{bed:$bed,tool:$tool}}')
    echo $ph_profile | jq

    while true; do
      read -p "Add profile \"$ph_name\"? [y/N]: " -n 1 yn
      echo ""
      case $yn in
        [yY])
          echo -n "Adding profile \"$ph_name\"..."
          jq --argjson profile "$ph_profile" \
            '.profiles += $profile' $ph_file > octo__temp__json \
            && mv octo__temp__json $ph_file \
          && echo "done" \
          && break

          echo "Error adding profile." >&2
          exit 1
          ;;
        [nN]) exit 0 ;;
        *) continue ;;
      esac
    done
  }

  function remove_profile() {
    case "$1" in
      "")
        while true; do
          read -p "Enter name of preheat profile for removal: " ph_name
          case "$ph_name" in
            *[[:space:]]*)
              echo "Error: Invalid input. Profile name cannot contain spaces." >&2
              ;;
            "") continue ;;
            *)
              if [ $(jq ".profiles | has(\"$ph_name\")" $ph_file ) == false ]; then
                echo "Error: Profile \"$ph_name\" does not exist." >&2
                echo "List preheat profiles with the following command:"
                echo "      $ProgramName -ph list"
                exit 1
              else break
              fi
              ;;
          esac
        done;;
      *)
        ph_name="$1"
        case "$ph_name" in
          *[[:space:]]*)
            echo "Error: Invalid input. Profile name cannot contain spaces." >&2
            ;;
          *)
            if [ $(jq ".profiles | has(\"$ph_name\")" $ph_file ) == false ]; then
              echo "Error: Profile \"$ph_name\" does not exist." >&2
              echo "List preheat profiles with the following command:"
              echo "      $ProgramName -ph list"
              exit 1
            else break
            fi
            ;;
        esac
    esac

    jq --arg name "$ph_name" '.profiles | to_entries | map(select(.key==$name)) | from_entries' $ph_file

    while true; do
      read -p "Remove profile \"$ph_name\"? [y/N]: " -n 1 yn
      echo ""
      case $yn in
        [yY])
          echo -n "Removing preheat profile \"$ph_name\"..."
          jq --arg name "$ph_name" \
            'del(.profiles | .[$name])' $ph_file > octo__temp__json \
            && mv octo__temp__json $ph_file \
          && echo "done" \
          && exit 0

          echo "Error removing profile." >&2
          exit 1
          ;;
        [nN]) exit 0 ;;
        *) continue ;;
      esac
    done
  }

  function list_profiles() {
    if [ $(jq 'any(.profiles; . == {})' $ph_file) == true ]; then
      echo "No preheat profiles found."
      echo ""
      echo "Add a preheat profile with the following command:"
      echo "      $ProgramName -ph add"
    else
      jq '.profiles' $ph_file
    fi
  }

  function preheat() {
    if [ $(jq ".profiles | has(\"$1\")" $ph_file ) == false ]; then
      echo "Error: Profile \"$1\" not found." >&2
      echo "Add a preheat profile with the following command:"
      echo "      $ProgramName -ph add"
      exit 1
    fi

    ph_bed=$(jq ".profiles.$1.bed" $ph_file)
    ph_tool=$(jq ".profiles.$1.tool" $ph_file)

    echo -n "Preheating Bed/Tool: $ph_bed/$ph_tool ??C..."
    octo__gcode --silent "M190 S$ph_bed; M104 S$ph_tool"
    echo "done"
  }

  create_ph_file

  case "$1" in
    "")
      echo "Error: Missing argument." >&2
      echo "Usage:"
      echo "      $ProgramName -ph <'profile name' | add | remove | list>"
      exit 1
      ;;

    "add")           add_profile ;;
    "remove") shift; remove_profile $@ ;;
    "list")          list_profiles ;;
    *)               preheat "$1" ;;
  esac
}

cmd="$1"
case "$cmd" in
  "" | "-h" | "--help") octo__help ;;
  "--sleep")                    shift; octo__sleep $@ ;;
  "-g" | "--gcode")             shift; octo__gcode "$@" ;;
  "-j" | "--job")               shift; octo__job $@ ;;
  "-p" | "--psu")               shift; octo__psu $@ ;;
  "-c" | "--connect")           shift; octo__connection "1" ;;
  "-d" | "--disconnect")        shift; octo__connection "0" ;;
  "-C" | "--connection")        shift; octo__connection $@ ;;
  "-F" | "--file")              shift; octo__file $@ ;;
  "-b" | "--bed")               shift; octo__bed $@ ;;
  "-t" | "--tool" | "--hotend") shift; octo__tool $@ ;;
  "-f" | "--fan")               shift; octo__fan $@ ;;
  "-ph" | "--preheat")          shift; octo__preheat $@ ;;
  "--on")                              octo__psu "1" ;;
  "--off")                             octo__psu "0" ;;
  "--toggle")                          octo__psu "toggle" ;;
  "--reboot")                          octo__psu "reboot" ;;
  "--start")                           octo__job "start" ;;
  "--cancel")                          octo__job "cancel" ;;
  "--restart")                         octo__job "restart" ;;
  "--pause")                           octo__job "pause" ;;
  "--resume")                          octo__job "pause" "resume" ;;
  "--time")                            octo__job "time" ;;
  "--select")                          octo__file "select" ;;
  "--unselect")                        octo__file "unselect" ;;
  "--cool" | "--cooldown")
    octo__bed 0
    octo__tool 0
    octo__fan 0
    ;;
  *)
    echo "Error: invalid syntax or '$cmd' is not a known command." >&2
    echo "    Run '$ProgramName --help' for a list of known commands."
    echo ""
    exit 1
    ;;
esac
