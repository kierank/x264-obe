W=/mnt/c/Users/kiera/AppData/Local/Temp/claude/e03b5c369dad1c6c/21f3df22-ec8f-4b2d-9d81-e76f5ec2f88e/scratchpad/me10
bash $W/hb.sh && taskset -c 2 ~/me10/harness10 ${1:-5} ${2:-15}
