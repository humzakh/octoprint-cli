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

for module in $(dirname "$0")/modules/octo_*.sh; do source $module; done

cmd="$1"
case "$cmd" in
  "" | "-h" | "--help" | "help") octo__help ;;
  "--sleep" | "sleep")                    shift; octo__sleep $@ ;;
  "-g" | "--gcode" | "gcode")             shift; octo__gcode "$@" ;;
  "-j" | "--job"  | "job")                shift; octo__job $@ ;;
  "-p" | "--psu" | "psu")                 shift; octo__psu $@ ;;
  "-c" | "--connect" | "connect")         shift; octo__connection "1" ;;
  "-d" | "--disconnect" | "disconnect")   shift; octo__connection "0" ;;
  "-C" | "--connection" | "connection")   shift; octo__connection $@ ;;
  "-F" | "--file" | "file")               shift; octo__file $@ ;;
  "-b" | "--bed" | "bed")                 shift; octo__bed $@ ;;
  "-t" | "--tool" | "--hotend" | "tool")  shift; octo__tool $@ ;;
  "-f" | "--fan" | "fan")                 shift; octo__fan $@ ;;
  "-ph" | "--preheat" | "ph" | "preheat") shift; octo__preheat $@ ;;
  "--on" | "on")                                 octo__psu "1" ;;
  "--off" | "off")                               octo__psu "0" ;;
  "--toggle" | "toggle")                         octo__psu "toggle" ;;
  "--reboot" | "reboot")                         octo__psu "reboot" ;;
  "--start" | "start")                           octo__job "start" ;;
  "--cancel" | "cancel" | "abort" | "stop")      octo__job "cancel" ;;
  "--restart" | "restart")                       octo__job "restart" ;;
  "--pause" | "pause")                           octo__job "pause" ;;
  "--resume" | "resume")                         octo__job "pause" "resume" ;;
  "--time" | "time")                             octo__job "time" ;;
  "--select" | "select")                         octo__file "select" ;;
  "--unselect" | "unselect")                     octo__file "unselect" ;;
  "--cool" | "--cooldown" | "cool" | "cooldown")
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
