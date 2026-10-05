# Run from the release folder, after this release's .bit is loaded via JTAG.
set pagination off
set confirm off
set print pretty on
set remotetimeout 30
file firmware/evsoc_tinyml_gesture.elf
target extended-remote localhost:3333
monitor halt
load
set $pc = _start
thbreak cnn_debug_done
continue
printf "\nStatic test stopped. Expected: stage=9, error=0, completed=3, passed=3.\n"
print cnn_debug_status
printf "\nIf the target stalls before this breakpoint, press Ctrl+C, then run:\n"
printf "p cnn_debug_status\ninfo registers pc mcause mepc mtval\nbt\n"
