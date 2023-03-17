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

function octo__bed() {
  local url="$server_url/api/printer/bed"
  case "$1" in
    [0-9] | [0-9][0-9] | [0-9][0-9][0-9])
      if [ "$1" -le "$max_bed_temp" ]; then
        echo -n "Setting bed temperature to $1 °C..."
        octo__gcode --silent "M140 S$1"
        echo "done"
      else
        echo "Error: Value too high. Max bed temperature: $max_bed_temp °C"
        exit 1
      fi
      ;;
    "off" | "cool" | "cooldown")
      echo -n "Setting bed temperature to 0 °C..."
      octo__gcode --silent "M140 S0"
      echo "done"
      ;;
    "level")
      echo -n "Leveling bed..."
      octo__gcode --silent 'M190 S60; G28; M155 S30; @BEDLEVELVISUALIZER; G29 T; M155 S3; M500'
      echo "done"
      exit 0
      ;;
    "" | "status") ;;
    *)
      echo "Error: Invalid argument." >&2
      echo "Usage:"
      echo "      $ProgramName --bed <off | [value in °C] | status>"
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
        echo -n "Setting tool temperature to $1 °C..."
        octo__gcode --silent "M104 S$1"
        echo "done"
      else
        echo "Error: Value too high. Max tool temperature: $max_tool_temp °C" >&2
        exit 1
      fi
      ;;
    "off" | "cool" | "cooldown")
      echo -n "Setting tool temperature to 0 °C..."
      octo__gcode --silent "M104 S0"
      echo "done"
      ;;
    "load")
      echo "Loading filament..."
      octo__gcode --silent "M701"
      exit 0
      ;;
    "unload")
      echo "Unloading filament..."
      octo__gcode --silent "M702"
      exit 0
      ;;
    "" | "status") ;;
    *)
      echo "Error: Invalid argument." >&2
      echo "Usage:"
      echo "      $ProgramName --tool <off | [value in °C] | status>"
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
        echo "Error: Value too high. Max bed temperature: $max_bed_temp °C" >&2
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
        echo "Error: Value too high. Max tool temperature: $max_tool_temp °C" >&2
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

    echo -n "Preheating Bed/Tool: $ph_bed/$ph_tool °C..."
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

        printf "\033[31mElapsed:   %02d:%02d:%02d\012" \
          $((printTime/3600)) $(((printTime/60)%60)) $((printTime%60))
        printf "\033[32mRemaining: %02d:%02d:%02d\012" \
          $((printTimeLeft/3600)) $(((printTimeLeft/60)%60)) $((printTimeLeft%60))
        printf "\033[34mOrigin:    $printTimeLeftOrigin\033[0m\012"
      else echo "Printer is not printing."
      fi
      exit 0
      ;;
    *);;
  esac
  >&2 echo "Retrieving job status..."
  get__request "$url"
}
