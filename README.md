# Git Flow Tools

### [release.ps1](./release.ps1)

Requirements:
- Powershell or Powershell Core (Tested on Windows, OS X, and Linux)

Usage:

- `pwsh /app/release.ps1 -create_release -version 100`
- `pwsh /app/release.ps1 -mark_released -version 100`

Features:

- Automates release branch creation, release branch cleanup, pushes to master, and git tagging
- Will notify after finishing a release if there are pending hotfix commits to be merged back into develop
- Will stop creating a new release if there are hotfix commits missing from develop

Hotfix to 103

This repo uses Github Actions for verifying the various git flow scenarios.


Test!
