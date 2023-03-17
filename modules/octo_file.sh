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