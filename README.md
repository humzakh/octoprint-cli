# octoprint-cli
### Control your 3D printer through a command line interface.


## Instructions

0. Set up [OctoPrint](https://octoprint.org/) 
1. Clone this repo
2. Grant execution permissions for the script
``` console
chmod +x octo.sh
```
3. Open ```octo.cfg``` and modify the Server/Printer config values.
  * OctoPrint API keys can be generated at ```OctoPrint Settings > Features > Application Keys```
4. Run the script
``` console
./octo.sh
```
#
#### Optional, but useful
Add the following function to your shell's rc file so that you can easily run the ```octo``` command.
``` console
function octo() { /PATH/TO/SCRIPT/octo.sh $@ }
```
#
```
Usage: octo.sh [command] <option>

Commands:

     help
          Display this help message.

     connect
          Connect to printer via serial port.

     disconnect
          Disconnect from printer.

     connection
          Display connection status.

     psu <on | off | toggle | reboot | status>
          Manage PSU state.
              Must have PSU Control plugin installed
              & configured in your Octoprint instance.
                https://plugins.octoprint.org/plugins/psucontrol
          Each of these PSU options can be sent as their own commands.
              e.g. on, off, reboot, etc.

     gcode <'G-code Commands' | help>
          Send G-code commands (semicolon separated) to printer.
          <help>: Display link to Marlin G-code documentation.

     select
          Select a file for printing from local storage.

     unselect
          Unselect currently selected file.

     job
          View current job status.

     start
          Start currently selected print job.

     cancel
          Abort currently running print job.

     pause
          Pause currently running print job.

     resume
          Resume currently paused print job.
    
     time
          Display elapsed/remaining time for current print job.

     bed <off | [value in °C] | status>
          Set heated bed temperature.

     tool <off | [value in °C] | status>
          Set tool/hotend temperature.

     fan <off | [0-100]% | [0-255]>
          Set cooling fan speed.

     preheat <'profile name' | add | remove | list>
          Preheat bed/tool using values in the given preheat profile.

     sleep <time in minutes>
          Display countdown timer for <minutes>.
          Useful for delaying subsequent commands.
              e.g. octo.sh sleep 10 && octo.sh start
                   (sleep for 10 minutes, then start print job)
```
