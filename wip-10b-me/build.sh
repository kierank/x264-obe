# usage: build.sh <bitdepth 8|10> <dst dir> [make targets]; builds the worktree (via /mnt/c) incrementally
set -e
BD=$1; DST=$2; shift 2
SRC=/mnt/c/Users/kiera/AppData/Local/Temp/claude/e03b5c369dad1c6c/21f3df22-ec8f-4b2d-9d81-e76f5ec2f88e/scratchpad/wt-10b-me
ST=$DST.stage
mkdir -p $DST $ST
rsync -rlp --delete --exclude .git $SRC/ $ST/
cd $ST
grep -rlI $'\r' --include='*.c' --include='*.h' --include='*.asm' --include='*.sh' --include=configure --include=Makefile --include='*.mak' . | xargs -r sed -i 's/\r$//'
rsync -rlpc --exclude '*.o' --exclude '*.a' --exclude config.mak --exclude config.h --exclude config.log --exclude cfg.log --exclude x264_config.h --exclude /checkasm8 --exclude /checkasm10 --exclude '/harness*' --exclude .depend $ST/ $DST/
cd $DST
if [ ! -f config.mak ]; then ./configure --bit-depth=$BD --disable-cli --enable-static --disable-opencl --extra-cflags=-fno-pie --extra-ldflags=-no-pie > cfg.log 2>&1 || { tail -20 cfg.log; exit 1; }; fi
make -j8 ${@:-checkasm$BD} 2>&1 | grep -E "error|Error|me-64" | head -40 || true
n0=$(find $DST -name "*.o" -size 0 | wc -l); [ $n0 = 0 ] || echo "ZERO-SIZE OBJECTS: $n0"
ls -la $DST/checkasm$BD 2>/dev/null || true
