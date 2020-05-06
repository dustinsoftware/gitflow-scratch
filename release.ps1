param(
  # The release version
  [string] $version,
  [switch] $create_release,
  [switch] $create_hotfix_release,
  [string] $hotfix_base_branch,
  [string] $hotfix_new_branch,
  # Mark a release as live
  [switch] $mark_released,
  # Skip pushing anything
  [switch] $safe_mode,
  [switch] $list_releases
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

if ($list_releases) {
  InvokeAndCheckExit "git fetch origin"
  $allRefs = InvokeAndCheckExit "git ls-remote origin"
  foreach ($branch in $allRefs | Select-String -Pattern "refs\/heads\/(release-\d+(?:-\d+)*$)" | % { "$($_.matches.groups[1])" } ) {
    Write-Output $branch
  }
}

if ($create_release) {
  InvokeAndCheckExit "git fetch origin"
  CheckForPendingBackmerge "develop"

  if ($version -eq "") {
    Write-Output "No version specified. Finding latest tag."
    $allTags = InvokeAndCheckExit "git ls-remote --tags origin"
    $maximum = ($allTags | Select-String -Pattern "refs\/tags\/v(\d+)" | % { "$($_.matches.groups[1])" } | Measure-Object -Maximum).Maximum
    $version = $maximum + 1
    Write-Output "Creating $version. Please type $version continue."
    if (!((Read-Host) -eq $version)) {
      throw "Sorry, cannot continue."
    }
  }
  $branch_name = GetBranchName $version

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

if ($create_hotfix_release) {
  if ($hotfix_base_branch -eq $null) {
    throw "Please specify -hotfix_base_branch"
  }
  if ($hotfix_new_branch -eq $null) {
    throw "Please specify -hotfix_new_branch"
  }
  if (!(DoesBranchExist "origin/$hotfix_base_branch")) {
    throw "Branch $hotfix_base_branch does not exist on remote"
  }
  $pendingMerges = InvokeAndCheckExit "git diff origin/$hotfix_base_branch...origin/master"
  if (!($pendingMerges -eq $null)) {
    throw "Backmerge required from master into $hotfix_base_branch first."
  }

  RunWithSafetyCheck "git checkout origin/$hotfix_base_branch"
  RunWithSafetyCheck "git checkout -b $hotfix_new_branch"
  RunWithSafetyCheck "git push origin $hotfix_new_branch"
}

if ($mark_released) {
  InvokeAndCheckExit "git fetch origin"

  $branch_name = GetBranchName $version

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

  # For any hotfix branches
  $allRefs = InvokeAndCheckExit "git ls-remote origin"
  foreach ($branch in $allRefs | Select-String -Pattern "refs\/heads\/(release-\d+(?:-\d+)*$)" | % { "$($_.matches.groups[1])" } )
  {
    $pendingMerges = InvokeAndCheckExit "git diff origin/$branch...origin/master"
    if ($pendingMerges -eq $null) {
      Write-Output "No backmerge required for $branch."
    } else {
      Write-Output "Backmerge required for $branch, please open: https://github.com/dustinsoftware/gitflow-scratch/compare/$branch...master?expand=1&title=Backmerge"
    }
  }
}
