# Git Flow Tools

### [release.ps1](./release.ps1)

Requirements:
- Powershell or Powershell Core (Tested on Windows, OS X, and Linux)

Usage:

- `pwsh /app/release.ps1 -list_releases`
- `pwsh /app/release.ps1 -create_release -version 100`
- `pwsh /app/release.ps1 -create_hotfix_release -version 100.1 -hotfix_base_branch master`
- `pwsh /app/release.ps1 -mark_released -version 100`
- `pwsh /app/release.ps1 -backmerge` (in case someone did not complete the backmerge steps during `-mark_released`)

To test out any of the commands above, pass `-safe_mode` as an argument. No changes will be made to the repo.

Features:

- Automates release branch creation, release branch cleanup, pushes to master, and git tagging (if -create_tag is specified)
- Will notify after finishing a release if there are pending hotfix commits to be merged back into develop
- Will stop creating a new release if there are hotfix commits missing from develop

This repo uses Github Actions for verifying the various git flow scenarios.
