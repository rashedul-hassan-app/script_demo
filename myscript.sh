#!/bin/bash

# Check if required commands are available
if ! command -v git &> /dev/null || ! command -v npm &> /dev/null || ! command -v jq &> /dev/null; then
    echo "git, npm, and jq are required to run this script."
    exit 1
fi

# Capture the current branch to return to it later
original_branch=$(git branch --show-current)

# Prompt the user to specify the starting commit (optional)
echo "Enter the starting commit hash (or leave blank to start from the first commit):"
read starting_commit

# If no starting commit is provided, start from the first commit
if [ -z "$starting_commit" ]; then
    starting_commit=$(git rev-list --max-parents=0 HEAD)
fi

# Stash any local changes before starting the script
echo "Stashing local changes..."
git stash --include-untracked

# Create an HTML report file
report_file="npm_install_report.html"

# Initialize the HTML file
echo "<html><head><title>NPM Install Time Report</title>" > $report_file
echo "<style>table { width: 100%; border-collapse: collapse; }" >> $report_file
echo "th, td { padding: 10px; text-align: left; border: 1px solid #ddd; }" >> $report_file
echo "th { background-color: #f4f4f4; }" >> $report_file
echo ".highlight { background-color: #ffdddd; }" >> $report_file
echo "</style></head><body><h1>NPM Install Time Report</h1>" >> $report_file
echo "<table>" >> $report_file
echo "<tr><th>Serial</th><th>Commit</th><th>Commit Message</th><th>Git Diff (package.json)</th><th>Time (s)</th></tr>" >> $report_file

# Initialize the summary variables
serial_number=0
total_commits=0
max_time=0
max_commit=""
max_git_diff=""

# Function to ensure the script checks out the original branch and restores stashed changes on exit
cleanup() {
    echo "Checking out the original branch: $original_branch"
    git checkout "$original_branch"
    echo "Applying stashed changes..."
    git stash pop || echo "No stashed changes to apply."
}
trap cleanup EXIT

# Get the list of commits starting from the specified commit
commits=$(git rev-list --reverse "$starting_commit"..HEAD)

# Start processing commits
echo "<h2>Summary</h2><ul>" >> $report_file

# Loop through each commit
for commit in $commits; do
    serial_number=$((serial_number + 1))
    total_commits=$((total_commits + 1))
    echo "Processing commit: $commit ($total_commits/$(echo "$commits" | wc -l))"

    # Checkout the commit
    git checkout "$commit"

    # Get the commit message
    commit_message=$(git log -1 --pretty=%B "$commit")

    # Capture the filtered git diff of package.json
    git_diff=$(git diff HEAD~1 HEAD -- package.json | grep '^[+-]    "' | grep -v 'package.json')

    # Clear the npm cache and remove node_modules to ensure a fresh install
    npm cache clean --force
    rm -rf node_modules

    # Measure the installation time
    start_time=$(date +%s)
    if ! npm install; then
        echo "npm install failed at commit $commit. Exiting."
        echo "<li>Installation failed at commit <strong>$commit</strong>.</li>" >> $report_file
        exit 1
    fi
    end_time=$(date +%s)
    elapsed_time=$((end_time - start_time))

    # Track the max time and associated git diff
    if (( elapsed_time > max_time )); then
        max_time=$elapsed_time
        max_commit=$commit
        max_git_diff="$git_diff"
    fi

    # Add the row to the HTML table
    echo "<tr>" >> $report_file
    echo "<td>$serial_number</td><td>$commit</td><td>$commit_message</td><td><pre>$git_diff</pre></td><td>$elapsed_time</td></tr>" >> $report_file

    echo "Commit $commit processed in $elapsed_time seconds."

done

# Finalize the summary in the HTML report
echo "<li>Total commits processed: $total_commits</li>" >> $report_file
echo "<li>Commit with the longest install time: <strong>$max_commit</strong> taking <strong>$max_time seconds</strong></li>" >> $report_file
echo "<li>Git diff of package.json for the slowest commit:<pre>$max_git_diff</pre></li>" >> $report_file
echo "</ul>" >> $report_file

# Finalize the HTML table and close the HTML document
echo "</table></body></html>" >> $report_file

echo "HTML report generated: $report_file"
echo "Summary:"
echo "Total commits processed: $total_commits"
echo "Commit with the longest install time: $max_commit taking $max_time seconds"
echo "See the full report in $report_file"
