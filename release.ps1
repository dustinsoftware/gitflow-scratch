param(
  # The release version
  [string] $version,
  [switch] $create_release,
  [switch] $create_hotfix_release,
  [string] $hotfix_base_branch,
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

function DoesRefExist {
  param([string] $ref)
  $output = Invoke-Expression "git show-ref $ref "
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
    throw "Version did not match the pattern 'major' or 'major.minor'. Eg. '123.4' instead of 'release-123-4'."
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
  if (!($Env:CI -eq '1')) {
    Write-Output "Current release branches:"
  }
  foreach ($branch in $allRefs | Select-String -Pattern "refs\/heads\/(release-\d+(?:-\d+)*$)" | % { "$($_.matches.groups[1])" } ) {
    Write-Output "Branch $branch"
  }

  if (!($Env:CI -eq '1')) {
    Write-Output "Last 5 tags:"
  }
  foreach ($branch in $allRefs | Select-String -Pattern "refs\/tags\/(.*)$" | % { "$($_.matches.groups[1])" } | Select -Last 5 ) {
    Write-Output "Tag $branch"
  }
}

if ($create_release) {
  InvokeAndCheckExit "git fetch origin"
  CheckForPendingBackmerge "develop"

  if ($version -eq "") {
    throw "No version specified. Please run -list_releases and then pass in a version with -version."
  }
  $branch_name = GetBranchName $version

  if (DoesRefExist "refs/remotes/origin/$branch_name") {
    throw "Branch $branch_name already exists on remote, please delete it and try again"
  }
  if (DoesRefExist "refs/heads/$branch_name") {
    throw "Branch $branch_name already exists locally, please delete it and try again"
  }

  if (!($Env:CI -eq '1')) {
    Write-Output "About to create $branch_name. Type OK to continue"
    if (!((Read-Host) -ieq 'ok')) {
      throw "Sorry, cannot continue."
    }
  }

  InvokeAndCheckExit "git checkout -q origin/develop"
  RunWithSafetyCheck "git checkout -b $branch_name"
  RunWithSafetyCheck "git push origin HEAD:$branch_name"

  Write-Output "Branch $branch_name created and pushed."
}

if ($create_hotfix_release) {
  if ($hotfix_base_branch -eq $null) {
    throw "Please specify -hotfix_base_branch"
  }
  if ($version -eq $null) {
    throw "Please specify -version"
  }

  $hotfix_new_branch = GetBranchName $version

  if (!(DoesRefExist "refs/remotes/origin/$hotfix_base_branch")) {
    throw "Branch $hotfix_base_branch does not exist on remote"
  }
  $pendingMerges = InvokeAndCheckExit "git diff origin/$hotfix_base_branch...origin/master"
  if (!($pendingMerges -eq $null)) {
    throw "Backmerge required from master into $hotfix_base_branch first."
  }

  if (!($Env:CI -eq '1')) {
    Write-Output "About to create $hotfix_new_branch based off of $hotfix_base_branch. Type OK to continue"
    if (!((Read-Host) -ieq 'ok')) {
      throw "Sorry, cannot continue."
    }
  }

  RunWithSafetyCheck "git checkout -q origin/$hotfix_base_branch"
  RunWithSafetyCheck "git checkout -b $hotfix_new_branch"
  RunWithSafetyCheck "git push origin $hotfix_new_branch"
}

if ($mark_released) {
  InvokeAndCheckExit "git fetch origin"

  $branch_name = GetBranchName $version

  if (!(DoesRefExist "refs/remotes/origin/$branch_name")) {
    throw "Branch $branch_name does not exist on remote"
  }
  if (!(DoesRefExist "refs/remotes/origin/master")) {
    throw "Branch master does not exist on remote"
  }

  CheckForPendingBackmerge "$branch_name"

  InvokeAndCheckExit "git checkout -q origin/$branch_name"

  if (!($Env:CI -eq '1')) {
    Write-Output "About to mark $branch_name as released and push tags for $version. Type OK to continue"
    if (!((Read-Host) -ieq 'ok')) {
      throw "Sorry, cannot continue."
    }
  }

  RunWithSafetyCheck "git tag v$version"
  RunWithSafetyCheck "git push origin HEAD:master"
  RunWithSafetyCheck "git push origin --tags"

  RunWithSafetyCheck "git branch -d $branch_name"
  RunWithSafetyCheck "git push origin -d $branch_name"

  $pendingMerges = InvokeAndCheckExit "git diff origin/develop...origin/master"
  if ($pendingMerges -eq $null) {
    Write-Output "No backmerge required to develop."
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
