param(
  # The release version
  [string] $version,
  [switch] $create_release,
  # Mark a release as live
  [switch] $mark_released,
  # Skip pushing anything
  [switch] $safe_mode
)

# Release script that enforces a one way commit history on master.

# How to test this:
# - Normal flow: develop -> rc-branch -> master
# - Hotfix flow: develop -> rc-branch -> hotfix into only rc-branch -> master
# - Two hotfix flow: develop -> rc-branch & rc-branch2 -> 2 hotfixes separately into rc-branch and rc-branch2 -> master
# - Missing hotfixes in develop when making a new branch or releasing an existing one (the latter is mostly a sanity check and would be bad if it happened on a real release)

$ErrorActionPreference = "Stop"

function InvokeAndCheckExit {
  param([string] $command)

  $output = Invoke-Expression $command

  if (!($LastExitCode -eq 0)) {
    Write-Output $output
    throw "Command did not run successfully."
  }

  return $output
}

function DoesBranchExist {
  param([string] $branch)
  $output = Invoke-Expression "git log -1 --pretty=%h $branch"
  if (!($LastExitCode -eq 0)) {
    return $false
  }
  return $true
}

function VerifyDirectory {
  param([string] $path)

  if (!(Test-Path $path)) {
    throw "$path was not found. Please clone it and try this script again."
  }
}

if (!(Test-Path "$PSScriptRoot\.git")) {
  Throw "The .git directory was not found locally."
}

function GetDirectoryGitHash() {
  param([string] $branch)
  return InvokeAndCheckExit "git log -1 --pretty=%h $branch"
}

function RunWithSafetyCheck() {
  param([string] $command)
  if ($safe_mode) {
    Write-Output "Skipping due to safe mode: $command"
  } else {
    InvokeAndCheckExit "$command"
  }
}

function CheckForPendingBackmerge() {
  param([string] $backmerge_branchname)
  $pendingMerges = InvokeAndCheckExit "git diff origin/$backmerge_branchname...origin/master"

  if (!($pendingMerges -eq $null)) {
    throw "master contains commits not merged back into $backmerge_branchname. Please fix that before proceeding. https://github.com/dustinsoftware/gitflow-scratch/compare/master?expand=1&title=Backmerge"
  }
}

function GetBranchName() {
  param([string] $version)

  $versionRegex = "(\d{3,})(?:\.(\d{1,}))?"
  if (!($version -match $versionRegex)) {
    throw "Version did not match the pattern 'major' or 'major.minor'"
  }

  $matchedVersion = $version | Select-String -Pattern $versionRegex
  $major = $matchedVersion.matches.groups[1].value
  $minor = $matchedVersion.matches.groups[2].value

  $branch_name = "release-$major"
  if (!($minor -eq "")) {
    $branch_name = "release-$major-$minor"
  }

  return $branch_name
}

if ($create_release) {
  InvokeAndCheckExit "git fetch origin"
  CheckForPendingBackmerge "develop"

  $branch_name = GetBranchName

  if (DoesBranchExist "origin/$branch_name") {
    throw "Branch $branch_name already exists on remote, please delete it and try again"
  }
  if (DoesBranchExist "$branch_name") {
    throw "Branch $branch_name already exists locally, please delete it and try again"
  }

  InvokeAndCheckExit "git checkout origin/develop"
  InvokeAndCheckExit "git checkout -b $branch_name"
  RunWithSafetyCheck "git push origin HEAD:$branch_name"

  Write-Output "Branch $branch_name created and pushed."
}

if ($mark_released) {
  InvokeAndCheckExit "git fetch origin"

  $branch_name = GetBranchName

  if (!(DoesBranchExist "origin/$branch_name")) {
    throw "Branch $branch_name does not exist on remote"
  }

  CheckForPendingBackmerge "$branch_name"

  InvokeAndCheckExit "git checkout origin/$branch_name"
  RunWithSafetyCheck "git tag v$version"
  RunWithSafetyCheck "git push origin HEAD:master"
  RunWithSafetyCheck "git push origin --tags"

  RunWithSafetyCheck "git branch -d $branch_name"
  RunWithSafetyCheck "git push origin -d $branch_name"

  $pendingMerges = InvokeAndCheckExit "git diff origin/develop...origin/master"
  if ($pendingMerges -eq $null) {
    Write-Output "No backmerge required."
  } else {
    Write-Output "Backmerge required, please open: https://github.com/dustinsoftware/gitflow-scratch/compare/master?expand=1&title=Backmerge"
  }
}
