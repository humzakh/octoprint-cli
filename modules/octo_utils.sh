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

function octo__sleep() {
  if ! [[ "$1" =~ ^[0-9]+$ ]]; then
    echo "Error: Invalid input." >&2
    echo "Usage:"
      echo "      $ProgramName sleep <time in minutes> && $ProgramName [other command]"
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