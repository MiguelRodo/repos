set -u
arr=()
echo "Length: ${#arr[@]}"
# This SHOULD NOT fail even in Bash 3.2 with set -u
echo ${arr[@]+"${arr[@]}"}
echo "End"
