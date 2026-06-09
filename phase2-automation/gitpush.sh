#!/bin/bash

export GIT_SSH_COMMAND="ssh -i /home/khlongwa/.ssh/id_ed25519" # This points to my GitHub private key

cd /home/khlongwa/Documents/sysadmin-lab || exit 1

# Pull latest from remote first
git pull origin main > /dev/null 2>&1

# Check if we are in a git repo
if ! git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
    exit 1
fi


# Check if there is anything to commit
if [ -z "$(git status --porcelain)" ]; then
    exit 0
fi



# Add changes
git add .

CHANGED_FILES=$(git diff --cached --name-only)
COMMIT_MSG="Automated backup: Synced files on $(date '+%Y-%m-%d %H:%M')"

# Commit with message and file list
git commit -m "$COMMIT_MSG" -m "$CHANGED_FILES" > /dev/null 2>&1

# Push
git push origin main > /dev/null 2>&1

