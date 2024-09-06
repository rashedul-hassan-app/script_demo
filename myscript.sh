#!/bin/bash

# Check if required commands are available
if ! command -v git &> /dev/null || ! command -v npm &> /dev/null; then
    echo "git and npm are required to run this script."
    exit 1
fi

# Create a report file
report_file="npm_install_report.txt"
echo "Commit, Time (s), Packages Added, Packages Removed" > $report_file

# Get the list of commits in the current branch
commits=$(git rev-list --reverse HEAD)

# Initialize previous package list to compare between commits
previous_packages=""

# Loop through each commit
for commit in $commits; do
    echo "Processing commit: $commit"

    # Checkout the commit
    git checkout $commit

    # Clear the npm cache and remove node_modules to ensure a fresh install
    npm cache clean --force
    rm -rf node_modules

    # Measure the installation time
    start_time=$(date +%s)
    npm install
    end_time=$(date +%s)
    elapsed_time=$((end_time - start_time))

    # List the current packages in package.json
    current_packages=$(cat package.json | jq -r '.dependencies, .devDependencies | keys[]' | sort)

    # Compare with the previous packages to find added and removed packages
    added_packages=$(comm -13 <(echo "$previous_packages") <(echo "$current_packages"))
    removed_packages=$(comm -23 <(echo "$previous_packages") <(echo "$current_packages"))

    # Save the results to the report file
    echo "$commit, $elapsed_time, \"$added_packages\", \"$removed_packages\"" >> $report_file

    # Update the previous packages list
    previous_packages="$current_packages"

done

# Checkout back to the original branch
git checkout -

echo "Report generated: $report_file"
