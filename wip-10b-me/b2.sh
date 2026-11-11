W=/mnt/c/Users/kiera/AppData/Local/Temp/claude/e03b5c369dad1c6c/21f3df22-ec8f-4b2d-9d81-e76f5ec2f88e/scratchpad/me10
[ -d ~/me10/c10 ] || cp -a ~/me10/b10 ~/me10/c10
bash $W/build.sh 10 ~/me10/c10 checkasm10
bash $W/hb.sh ~/me10/c10 ~/me10/c10/harness10
cd ~/me10/c10 && taskset -c 2 ./harness10 ${1:-2} 2>&1 | tail -4
