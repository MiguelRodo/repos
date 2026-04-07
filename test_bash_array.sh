set -u
arr=()
echo "Start"
# This would fail on Bash 3.2
echo "${arr[@]}"
echo "End"
