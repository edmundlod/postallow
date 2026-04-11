#!/bin/bash

# Usage: ./extract_domains_one_per_line.sh path/to/original_file_with_hosts.txt
# Output: A file in this directory with one domain per line, extracted from the input file.

# Fail if no argument (input file) is provided
if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <input_file>"
  exit 1
fi

input_file="$1"

# Check if the input file exists
if [[ ! -f "$input_file" ]]; then
  echo "Error: File not found: $input_file"
  exit 1
fi

# Process the file and write to domains_line.txt
awk '
  BEGIN { ORS = " " }
  /="/ {
    gsub(/.*="/, "")
    inlist = 1
  }
  inlist {
    gsub(/\\/, "")
    printf "%s", $0
  }
  /"/ {
    gsub(/".*/, "")
    print ""
    inlist = 0
  }
' "$input_file" > domains_one_per_line.txt
#|
#tr ' ' '\n' |
#sed -E '
#  s/^[[:space:]]+//;
#  s/[[:space:]]+$//;
#  s/"$//
#' |
#grep -vE '^$|^_' |
#awk '{ printf "\"%s\", ", $0 }' |
#sed 's/, $//' > domains_one_per_line.txt

# Add a final newline
#echo >> domains_one_per_line.txt
