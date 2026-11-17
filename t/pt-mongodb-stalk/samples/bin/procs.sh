# Sourced by the fake ps and lsof.  FAKE_PROCS lists the local MongoDB
# processes as "pid:name:port:elapsed-seconds:cpu" entries separated by
# spaces.  By default, the mongod the fake mongosh reports runs here.
FAKE_PROCS="${FAKE_PROCS-4242:mongod:27018:1000:12.5}"

# Print the entry of a PID, or of the process listening on a port, as
# "pid name port elapsed cpu".
fake_proc() {
   local by="$1" value="$2" entry
   for entry in $FAKE_PROCS; do
      set -- $(echo "$entry" | tr ':' ' ')
      if { [ "$by" = pid ] && [ "$1" = "$value" ]; } \
         || { [ "$by" = port ] && [ "$3" = "$value" ]; }; then
         echo "$1 $2 $3 $4 $5"
         return 0
      fi
   done
   return 1
}
