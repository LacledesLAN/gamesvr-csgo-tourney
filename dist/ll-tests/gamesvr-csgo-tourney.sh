#!/bin/bash -i

#####################################################################################################
### CONFIG VARS #####################################################################################
declare LLTEST_CMD="/app/srcds_run -game csgo +game_type 0 +game_mode 1 +map de_lltest -insecure -tickrate 128 -norestart +sv_lan 1";
declare LLTEST_NAME="gamesvr-csgo-tourney-$(date '+%H%M%S')";
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
        echo $"[FAIL] - $2" >> "$LLTEST_RESULTSFILE";
        LLTEST_HASFAILURES=true;
    else
        echo $"[PASS] - $2" >> "$LLTEST_RESULTSFILE";
    fi;
}

# Server log file should NOT contain $1 because $2
function should_lack() {
    if grep -i -q "$1" "$LLTEST_LOGFILE"; then
        echo $"[FAIL] - $2" >> "$LLTEST_RESULTSFILE";
        LLTEST_HASFAILURES=true;
    else
        echo $"[PASS] - $2" >> "$LLTEST_RESULTSFILE";
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
should_lack 'map load failed:' 'Server was able to load custom-content the map'

# LL Settings
should_have 'Server logging enabled.' 'Logging is enabled';
should_have 'Server logging data to file logs/' 'Server is logging to the logs directory';

# Check SourceMod/MetaMod plugins
should_lack 'Host_Error: DLL_Crosshairangle: not a client' '2019.03.28 bug not found (https://forums.alliedmods.net/showthread.php?t=315229)'
#should_have '[SM/MM Information]' 'Meta Mod and Source Mod are both running';
#should_have '===BEGIN SERVER STATUS===' 'LL status mod ran';
#should_lack '<Error> "' 'LL status mod is not showing any SM plugins with errors'
#should_have '"Server Status-LL MOD" (' 'LL status mod reports itself';
#should_have '"Admin File Reader" (' 'LL status mod reports admin file reader';
#should_have '"Log Connections - LL Mod" (' 'LL status mod reports LL version of "log connections"';
#should_have '"Basic Comm Control" (' 'LL status mod reports basic comm control';
#should_have '"Basic Info Triggers" (' 'LL status mod reports basic info triggers';
#should_have '"Anti-Flood" (' "LL status mod reports anti-flood";
#should_have '"Basic Votes" (' "LL status mod reports basic votes";

# Verify server responds to commands
should_echo "say STARTING COMMAND TESTS" 'Console: STARTING COMMAND TESTS';
should_echo "sv_cheats" '"sv_cheats" = "0" notify replicated';
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
