#!/bin/sh
#####################
### SERVER CONFIG ###
#####################
api_key="$OCTO_API_KEY"
server_url="http://octopi.local"
#####################
### PRINTER CONFIG ##
#####################
max_bed_temp=140
max_hotend_temp=260
#####################
#####################
ProgramName=$(basename $0)

octo__help() {
    echo "Usage: $ProgramName <command> [option]\n"
    echo "Commands:"
    echo "    connect"
    echo "    disconnect"
    echo "    psu [on | off | toggle | status]"
    echo "    gcode ['G-code Command' | help]"
    echo "    job [start | cancel | resume | pause]"
    echo "    bed [off | 'value in °C']"
    echo "    hotend [off | 'value in °C']"
    echo "    fan [off | <0-100>% | <0-255>]"
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
            get__request "$url" ;;
    esac
}

octo__psu() {
    local url="$server_url/api/plugin/psucontrol"

    local cmd=""
    case $(echo "$1" | tr '[:upper:]' '[:lower:]') in
        "0" | "off")
            cmd="turnPSUOff" ;;
        "1" | "on")
            cmd="turnPSUOn" ;;
        "t" | "toggle")
            cmd="togglePSU" ;;
        *)
            cmd="getPSUState" ;;
    esac

    if [[ "$cmd" != "getPSUState" ]]; then
        post__request "$cmd" "$url"
    fi

    post__request "getPSUState" "$url"
}

octo__connection() {
    local url="$server_url/api/connection"

    case "$1" in
        "0")
            post__request "disconnect" "$url" ;;
        "1")
            post__request "connect" "$url" ;;
        *)
            get__request "$url" ;;
    esac
}

octo__bed() {
    local url="$server_url/api/printer/bed"
    case "$1" in
        [0-9] | [0-9][0-9] | [0-9][0-9][0-9])
            if [ "$1" -le "$max_bed_temp" ]; then
                octo__gcode "M140 S$1"
            else
                echo "Value too high. Max bed temp: $max_bed_temp"
            fi
            ;;
        "off" | "cool" | "cooldown")
            octo__gcode "M140 S0" ;;
        *)
            get__request "$url" ;;
    esac
}

octo__hotend() {
    local url="$server_url/api/printer/tool"

    case "$1" in
        [0-9] | [0-9][0-9] | [0-9][0-9][0-9])
            if [ "$1" -le "$max_hotend_temp" ]; then
                octo__gcode "M104 S$1"
            else
                echo "Value too high. Max hotend temp: $max_hotend_temp"
            fi
            ;;
        "off" | "cool" | "cooldown")
            octo__gcode "M104 S0" ;;
        *)
            get__request "$url" ;;
    esac
}

octo__fan() {
    case "$1" in
        "")
            echo "Fan speed: Missing argument. <0-255> or <0-100>%" ;;
        [0-9] | [0-9][0-9] | [0-9][0-9][0-9])
            if [ "$1" -le 255 ]; then
                octo__gcode "M106 S$1"
            else
                echo "Value too high. Max fan speed: 255"
            fi
            ;;
        [0-9]% | [0-9][0-9]% | [0-9][0-9][0-9]%)
            percentage=${1%\%}
            if [ "$percentage" -le 100 ] && [ "$percentage" -ge 0 ]; then
                val=$(( 255*percentage/100 ))
                octo__gcode "M106 S$val"
            else
                echo "Fan speed: Invalid argument."
            fi
            ;;
        "off")
            octo__gcode "M106 S0" ;;
        *)
            echo "Fan speed: Invalid argument." ;;
    esac
}

cmd=$(echo "$1" | tr '[:upper:]' '[:lower:]')
case $cmd in
    "" | "--help")
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
    "-b" | "--bed")
        shift
        octo__bed $@
        ;;
    "-h" | "--hotend")
        shift
        octo__hotend $@
        ;;
    "-f" | "--fan")
        shift
        octo__fan $@
        ;;
    *)
        shift
        octo__${cmd} $@
        if [ $? = 127 ]; then
            echo ""
            echo "Error: '$cmd' is not a known command." >&2
            echo "       Run '$ProgramName --help' for a list of known commands." >&2
            echo ""
            exit 1
        fi
        ;;
esac
