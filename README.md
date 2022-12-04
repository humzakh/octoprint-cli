# octoprint-cli
### Control your 3D printer through a command line interface.


## Instructions

1. Clone this repo
2. Grant execution permissions for the script
``` console
chmod +x octo.sh
```
3. Open ```octo.cfg``` and modify the Server/Printer configs.
  * OctoPrint API keys can be generated at ```OctoPrint Settings > Features > Application Keys```
4. Run the script
``` console
./octo.sh
```
#
#### Optional, but useful
Add the following function to your shell's rc file so that you can easily run the ```octo``` command.
``` console
function octo() { /{PATH TO SCRIPT}/octo.sh $@ }
```
#
```
Usage: octo.sh [command] <option>

Commands:

    -h, --help
         Print this help message.

    -c, --connect
         Connect to printer via serial port.

    -d, --disconnect
         Disconnect from printer.

    -C, --connection
         Print connection status.

    -p, --psu <on | off | toggle | reboot | status>
         Manage PSU state.
             Must have PSU Control plugin installed
             & configured in your Octoprint instance.
               https://plugins.octoprint.org/plugins/psucontrol
         <reboot>: Turns PSU off, waits 5 seconds, turns PSU on.

    -g, --gcode <'G-code Commands' | help>
         Send G-code commands (semicolon separated) to printer.
         <help>: Display link to Marlin G-code documentation.

    -s, --select
         Select a file for printing from local storage.

    -u, --unselect
         Uneselect currently selected file.

    -j, --job
         View current job status.

    -S, --start
         Start print job.

    -C, --cancel, --abort
         Abort running print job.

    -P, --pause
         Pause running print job.

    -R, --resume
         Resume paused print job.

    -b, --bed <off | [value in °C] | status>
         Set heated bed temperature.

    -t, --tool, --hotend <off | [value in °C] | status>
         Set tool/hotend temperature.

    -f, --fan <off | [0-100]% | [0-255]>
         Set cooling fan speed.

    -ph, --preheat <'profile name' | add | list>
         Preheat bed/tool using values in the given preheat profile.
```
