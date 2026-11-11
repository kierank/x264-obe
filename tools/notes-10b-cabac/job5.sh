S=/mnt/c/Users/kiera/AppData/Local/Temp/claude/e03b5c369dad1c6c/21f3df22-ec8f-4b2d-9d81-e76f5ec2f88e/scratchpad/cab10
{
export XSYM=x264_10_cabac_block_residual_rd2_internal_avx512icl XKIND=0
export X1D=-DRD4_ICL_LEVELS_MIN=0 X1N=i0 X2D=-DRD4_ICL_LEVELS_MIN=1 X2N=i1 X3D=-DRD4_ICL_LEVELS_MIN=3 X3N=i3 X4D=-DRD4_ICL_LEVELS_MIN=5 X4N=i5
DRVX="-DK4=1 -DK8=1 -DK422=1 -DICL2" bash $S/build.sh 2>&1 | grep -v "warning\|from macro\|^$"
cd /tmp/cab10
bash $S/evex.sh new.o | head -3
for d in drvx drv_pic; do echo "== $d"; timeout 600 taskset -c 2 ./$d test 1500; done
taskset -c 2 ./drvx ibench > /dev/null
for r in 1 2; do taskset -c 2 ./drvx ibench | grep rd4x4; done
} > $S/job5.out 2>&1
true
