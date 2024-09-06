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

# Create an HTML report file
report_file="npm_install_report.html"

# Initialize the HTML file
echo "<html><head><title>NPM Install Time Report</title>" > $report_file
echo "<style>table { width: 100%; border-collapse: collapse; }" >> $report_file
echo "th, td { padding: 10px; text-align: left; border: 1px solid #ddd; }" >> $report_file
echo "th { background-color: #f4f4f4; }" >> $report_file
echo ".green { background-color: #d4edda; }" >> $report_file
echo ".yellow { background-color: #fff3cd; }" >> $report_file
echo ".red { background-color: #f8d7da; }" >> $report_file
echo ".highlight { background-color: #ffdddd; }" >> $report_file
echo "</style></head><body><h1>NPM Install Time Report</h1>" >> $report_file
echo "<table>" >> $report_file
echo "<tr><th>Commit</th><th>Libraries Added</th><th>Libraries Removed</th><th>Time (s)</th><th>Feedback</th></tr>" >> $report_file

# Initialize the summary variables
total_commits=0
max_time=0
max_commit=""
max_added_packages=""
max_removed_packages=""

# Function to ensure the script checks out the original branch on exit
cleanup() {
    echo "Checking out the original branch: $original_branch"
    git checkout "$original_branch"
}
trap cleanup EXIT

# Get the list of commits starting from the specified commit
commits=$(git rev-list --reverse "$starting_commit"..HEAD)

# Initialize previous package list to compare between commits
previous_packages=""

# Start processing commits
echo "<h2>Summary</h2><ul>" >> $report_file

# Loop through each commit
for commit in $commits; do
    total_commits=$((total_commits + 1))
    echo "Processing commit: $commit ($total_commits/$(echo "$commits" | wc -l))"

    # Checkout the commit
    git checkout "$commit"

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

    # List the current packages in package.json
    current_packages=$(cat package.json | jq -r '.dependencies, .devDependencies | keys[]' | sort)

    # Compare with the previous packages to find added and removed packages
    added_packages=$(comm -13 <(echo "$previous_packages") <(echo "$current_packages"))
    removed_packages=$(comm -23 <(echo "$previous_packages") <(echo "$current_packages"))

    # Determine feedback color based on time
    if (( elapsed_time <= 30 )); then
        feedback_class="green"
    elif (( elapsed_time <= 60 )); then
        feedback_class="yellow"
    else
        feedback_class="red"
    fi

    # Track the max time and associated packages
    if (( elapsed_time > max_time )); then
        max_time=$elapsed_time
        max_commit=$commit
        max_added_packages="$added_packages"
        max_removed_packages="$removed_packages"
    fi

    # Add the row to the HTML table
    echo "<tr class=\"$feedback_class\">" >> $report_file
    echo "<td>$commit</td><td><pre>$added_packages</pre></td><td><pre>$removed_packages</pre></td><td>$elapsed_time</td><td class=\"$feedback_class\"></td></tr>" >> $report_file

    # Update the previous packages list
    previous_packages="$current_packages"

    echo "Commit $commit processed in $elapsed_time seconds."

done

# Finalize the summary in the HTML report
echo "<li>Total commits processed: $total_commits</li>" >> $report_file
echo "<li>Commit with the longest install time: <strong>$max_commit</strong> taking <strong>$max_time seconds</strong></li>" >> $report_file
echo "<li>Packages added in this commit:<pre>$max_added_packages</pre></li>" >> $report_file
echo "<li>Packages removed in this commit:<pre>$max_removed_packages</pre></li>" >> $report_file
echo "</ul>" >> $report_file

# Finalize the HTML table and close the HTML document
echo "</table></body></html>" >> $report_file

echo "HTML report generated: $report_file"
echo "Summary:"
echo "Total commits processed: $total_commits"
echo "Commit with the longest install time: $max_commit taking $max_time seconds"
echo "See the full report in $report_file"
