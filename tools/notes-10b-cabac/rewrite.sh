# rebuild the branch: real checkasm lines, notes squashed. Run in the worktree (Git Bash).
set -e
G="git -c core.autocrlf=false"
CK="checkasm10 seeds 1-5 on this commit and checkasm8 seeds 1-5 on the tip (also on d57d/873f, the commits that touch 8-bit checkasm code): all tests pass (laptop/Zen 5). The 8-bit libx264.a of the tip is byte-identical to d625b235's."
NOTES=$($G rev-parse HEAD)
$G reset -q --hard d625b235
for c in d57d0370 7641d69e bcc7df8d 5cf6d4ae 873f5dea 3b31def8 a2d60ded d679c1cb d04be24f 2b83c12c 241bb592; do
  $G cherry-pick $c > /dev/null
  if [ $c = d679c1cb ]; then $G checkout $NOTES -- tools/notes-10b-cabac; $G add tools/notes-10b-cabac; fi
  $G log -1 --format=%B $c | sed "s|^@CHECKASM@$|$CK|" > /tmp/msg.txt
  $G commit -q --amend -F /tmp/msg.txt
done
$G diff --stat $NOTES HEAD
$G log --oneline d625b235..HEAD
