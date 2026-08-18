#!/bin/bash

echo "Started"

cd /home/guruyadav/sre-projects

git_status=$(git status)

echo "$git_status"

if echo "$git_status" | grep -q "nothing to commit, working tree clean"; then
    echo "No changes found. Exiting..."
    exit 0
elif echo "$git_status" | grep -q "Untracked files"; then
    echo "Untracked files found. Continuing..."
else
    echo "Changes found. Continuing..."
fi

git add .

git commit -m "new update"

git push

echo "Push completed successfully"
