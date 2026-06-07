#!/bin/bash

cd /home/khlongwa/Documents/sysadmin-lab || exit 1

# Pull latest from remote first
git pull origin main

# Check if we are in a git repo
if ! git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
    exit 1
fi


# Check if there is anything to commit
if git diff --quiet && git diff --staged --quiet; then
    exit 0
fi



# Add changes
git add .

CHANGED_FILES=$(git diff --cached --name-only)
COMMIT_MSG="Automated backup: Synced files on $(date '+%Y-%m-%d %H:%M')"

# Commit with message and file list
git commit -m "$COMMIT_MSG" -m "$CHANGED_FILES"

# Push
git push origin main

