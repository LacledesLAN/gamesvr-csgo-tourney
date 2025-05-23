#!/bin/bash -i

#####################################################################################################
### CONFIG VARS #####################################################################################
declare LLTEST_CMD="/app/srcds_run -game csgo +game_type 0 +game_mode 1 +map de_nuke -insecure -tickrate 128 -norestart +sv_lan 1";
declare LLTEST_NAME="gamesvr-csgo-warmod-latest$(date '+%H%M%S')";
#####################################################################################################
#####################################################################################################

# Runtime vars
declare LLCOUNTER=0;
declare LLBOOT_ERRORS="";
declare LLTEST_HASFAILURES=false;
declare LLTEST_LOGFILE="$LLTEST_NAME"".log";
declare LLTEST_RESULTSFILE="$LLTEST_NAME"".results";

# Server log file should contain $1 because $2
function should_have() {
    if ! grep -i -q "$1" "$LLTEST_LOGFILE"; then
        echo $"[FAIL] - '$2'" >> "$LLTEST_RESULTSFILE";
        LLTEST_HASFAILURES=true;
    else
        echo $"[PASS] - '$2'" >> "$LLTEST_RESULTSFILE";
    fi;
}

# Server log file should NOT contain $1 because $2
function should_lack() {
    if grep -i -q "$1" "$LLTEST_LOGFILE"; then
        echo $"[FAIL] - '$2'" >> "$LLTEST_RESULTSFILE";
        LLTEST_HASFAILURES=true;
    else
        echo $"[PASS] - '$2'" >> "$LLTEST_RESULTSFILE";
    fi;
}

# Command $1 should make server return $2
function should_echo() {
    tmux has-session -t "$LLTEST_NAME" 2>/dev/null;
    if [ "$?" == 0 ] ; then
        LLCOUNTER=0;
        LLTMP=$(md5sum "$LLTEST_LOGFILE");
        tmux send -t "$LLTEST_NAME" C-z "$1" Enter;

        while true; do
            sleep 0.5;

            if  (( "$LLCOUNTER" > 30)); then
                echo $"[FAIL] - Command '$!' TIMED OUT";
                LLTEST_HASFAILURES=true;
                break;
            fi;

            if [[ $(md5sum "$LLTEST_LOGFILE") != "$LLTMP" ]]; then
                should_have "$2" "'$1' should result in '$2' (loop iterations: $LLCOUNTER)";
                break;
            fi;

            (( LLCOUNTER++ ));
        done;
    else
        echo $"[ERROR]- Could not run command '$1'; tmux session not found" >> "$LLTEST_RESULTSFILE";
        LLTEST_HASFAILURES=true;
    fi;
}

function print_log() {
    if [ ! -s "$LLTEST_LOGFILE" ]; then
        echo $'\nOUTPUT LOG IS EMPTY!\n';
        exit 1;
    else
        echo $'\n[LOGFILE OUTPUT]';
        awk '{print "»»  " $0}' "$LLTEST_LOGFILE";
    fi;
}

# Check prereqs
command -v awk > /dev/null 2>&1 || echo "awk is missing";
command -v md5sum > /dev/null 2>&1 || echo "md5sum is missing";
command -v sleep > /dev/null 2>&1 || echo "sleep is missing";
command -v tmux > /dev/null 2>&1 || echo "tmux is missing";

# Prep log file
: > "$LLTEST_LOGFILE"
if [ ! -f "$LLTEST_LOGFILE" ]; then
    echo 'Failed to create logfile: '"$LLTEST_LOGFILE"'. Verify file system permissions.';
    exit 2;
fi;

# Prep results file
: > "$LLTEST_RESULTSFILE"
if [ ! -f "$LLTEST_RESULTSFILE" ]; then
    echo 'Failed to create logfile: '"$LLTEST_RESULTSFILE"'. Verify file system permissions.';
    exit 2;
fi;

echo $'\n\nRUNNING TEST: '"$LLTEST_NAME";
echo $'Command: '"$LLTEST_CMD";
echo "Running under $(id)"$'\n';

# Execute test command in tmux session
tmux new -d -s "$LLTEST_NAME" "sleep 0.5; $LLTEST_CMD";
sleep 0.3;
tmux pipe-pane -t "$LLTEST_NAME" -o "cat > $LLTEST_LOGFILE";

while true; do
    tmux has-session -t "$LLTEST_NAME" 2>/dev/null;
    if [ "$?" != 0 ] ; then
        echo $'terminated.\n';
        LLBOOT_ERRORS="Test process self-terminated";
        break;
    fi;

    if  (( "$LLCOUNTER" >= 29 )); then
        if [ -s "$LLTEST_LOGFILE" ] && ((( $(date +%s) - $(stat -L --format %Y "$LLTEST_LOGFILE") ) > 20 )); then
            echo $'succeeded.\n';
            break;
        fi;

        if (( "$LLCOUNTER" > 120 )); then
            echo $'timed out.\n';
            LLBOOT_ERRORS="Test timed out";
            break;
        fi;
    fi;

    if (( LLCOUNTER % 5 == 0 )); then
        echo -n "$LLCOUNTER...";
    fi;

    (( LLCOUNTER++ ));
    sleep 1;
done;

if [ ! -s "$LLTEST_LOGFILE" ]; then
    echo $'\nOUTPUT LOG IS EMPTY!\n';
    exit 1;
fi;

if [ ! -z "${LLBOOT_ERRORS// }" ]; then
    echo "Boot error: $LLBOOT_ERRORS";
    print_log;
    exit 1;
fi;

#####################################################################################################
### TESTS ###########################################################################################
# Stock CSGO server tests
should_have 'Setting breakpad minidump AppID = 740' 'Sever started executing';
should_lack 'Server restart in 10 seconds' 'Server is not boot-looping';
should_lack 'Running the dedicated server as root' 'Server is not running under root';
should_have 'Game.dll loaded for "Counter-Strike: Global Offensive"' 'srcds_run loaded CSGO';
should_have 'Server is hibernating' 'srcds_run succesfully hibernated';
should_lack 'map load failed:' 'Server was able to load custom-content the map';
should_lack 'Your server needs to be restarted in order to receive the latest update.' 'Server is not reporting itself as out of date';
should_echo 'version' 'Exe version'

# Logging Settings
should_have 'Server logging enabled.' 'Logging is enabled';
should_have 'Server logging data to file logs/' 'Server is logging to the logs directory';

# Verify server responds to commands
should_echo "say STARTING COMMAND TESTS" 'Console: STARTING COMMAND TESTS';
should_echo "sv_cheats" '"sv_cheats" = "0" notify replicated';

# Check Metamod:Source
should_echo 'meta version' ' Metamod:Source Version Information'

# Check SourceMod:Source plugins
should_echo 'sm plugins list' '\[SM\] Listing'
should_lack 'Unknown command "sm"' 'sm command should be working'
## general checks
should_lack 'Successfully updated gamedata file "' 'SourceMod is not self updating'
should_lack 'SourceMod has been updated, please reload it or restart your server' 'SourceMod is not requesting restart'
should_lack 'Host_Error: DLL_Crosshairangle: not a client' '2019.03.28 bug not found (https://forums.alliedmods.net/showthread.php?t=315229)'
should_lack '<Error>' 'no sm plugins showing error state';
## expected plugins
should_have '\[BFG\] WarMod' 'LLWarMod';
should_have 'Admin File Reader' 'Admin file reader plugin';
should_have 'Anti-Flood' "anti-flood plugin";
should_have 'Basic Comm Control' 'Basic comm control plugin';
should_have 'Basic Info Triggers' 'Basic info triggers plugin';
should_have 'Log Connections - LL Mod' 'LL version of "log connections" plugin';
## unexpected plugins
should_lack ' "Fun Commands' "source mod plugin 'fun commands' should not be loaded"
should_lack ' "Fun Votes' "source mod plugin 'fun votes' should not be loaded"
should_lack ' "Nextmap' "source mod plugin 'nextmap' should not be loaded"
should_lack ' "Reserved Slots' "source mod plugin 'reserved slots' should not be loaded"
should_lack ' "Sound Commands" (' "source mod plugin 'sound commands' should not be loaded"

## Warmod checks
should_have 'WarMod \[BFG\] WarmUp Config Loaded' 'WarMod loaded config properly';



# Verify gamemode_competitive_server.cfg
echo "...using gamemode_competitive_server.cfg";
should_echo "exec gamemode_competitive_server.cfg" '"running gamemode_competitive_server.cfg"'; sleep 2;
should_echo "mp_friendlyfire" 'mp_friendlyfire" = "1"';
should_echo "mp_forcecamera" '"mp_forcecamera" = "1"';
should_echo "mp_startmoney" '"mp_startmoney" = "800"';
should_echo "mp_match_can_clinch" '"mp_match_can_clinch" = "1"';
should_echo "mp_maxrounds" '"mp_maxrounds" = "30"';
should_echo "mp_round_restart_delay" '"mp_round_restart_delay" = "5"';
should_echo "mp_roundtime" '"mp_roundtime" = "1.92"';
should_echo "mp_roundtime_defuse" '"mp_roundtime_defuse" = "1.92"';
should_echo "wm_auto_knife" '"wm_auto_knife" = "1"';

# Verify ruleset_default.cfg
echo "...using /warmod/ruleset_default.cfg";
should_echo "exec /warmod/ruleset_default.cfg" '"running warmod/ruleset_default.cfg"'; sleep 2;
should_echo "mp_overtime_enable" '"mp_overtime_enable" = "1"';

# Verify /warmod/ruleset_default.cfg
echo "...using /warmod/ruleset_default.cfg" '';
should_echo "exec /warmod/ruleset_default.cfg" ''; sleep 2;
should_echo "mp_overtime_maxrounds" '"mp_overtime_maxrounds" = "7"';

# Verify /warmod/ruleset_playout.cfg
echo "...using /warmod/ruleset_playout.cfg" '';
should_echo "exec /warmod/ruleset_playout.cfg" ''; sleep 2;
should_echo "mp_overtime_maxrounds" '"mp_overtime_maxrounds" = "7"';

# Verify /warmod/ruleset_overtime.cfg
echo "...using /warmod/ruleset_overtime.cfg";
should_echo "exec /warmod/ruleset_overtime.cfg" '"running warmod/ruleset_global.cfg"'; sleep 2;
should_echo "mp_overtime_enable" '"mp_overtime_enable" = "1"';
should_echo "mp_overtime_maxrounds" '"mp_overtime_maxrounds" = "7"';
should_echo "mp_overtime_startmoney" '"mp_overtime_startmoney" = "10000"';
#####################################################################################################
#####################################################################################################

tmux has-session -t "$LLTEST_NAME" 2>/dev/null;
if [ "$?" == 0 ] ; then
    tmux kill-session -t "$LLTEST_NAME";
fi;

print_log;

echo $'\n[TEST RESULTS]\n';
cat "$LLTEST_RESULTSFILE";

echo $'\n[OUTCOME]\n';
if [ $LLTEST_HASFAILURES = true ]; then
    echo $'Checks have failures!\n\n';
    exit 1;
fi;

echo $'All checks passed!\n\n';
exit 0;
