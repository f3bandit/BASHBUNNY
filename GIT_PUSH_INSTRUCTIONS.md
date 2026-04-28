# Git Push Instructions

## One-time setup (if not already done)

```bash
cd C:\Users\f3ban\OneDrive\Documents\GitHub\BASHBUNNY
git config user.name "f3bandit"
git config user.email "your@email.com"
```

## After extracting the zip to your repo folder

```bash
cd C:\Users\f3ban\OneDrive\Documents\GitHub\BASHBUNNY

# Stage all changes
git add README.md
git add docs/
git add scripts/

# Commit
git commit -m "Add v27 installer, docs, package list, conflict notes, test script"

# Push
git push origin main
```

## If you get a push rejection (remote has newer commits)

```bash
git pull --rebase
git push origin main
```

## Verify the push worked

```bash
git log --oneline -5
git status
```

Should show:
```
Your branch is up to date with 'origin/main'.
nothing to commit, working tree clean
```
