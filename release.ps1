param(
  # The release version
  [string] $version,
  # Skip Windows containers warning
  [switch] $create_release,
  # Mark a release as live
  [switch] $mark_released,
  # Skip pushing anything
  [switch] $safe_mode
)
$ErrorActionPreference = "Stop"
$versionRegex = "(\d{3,})(?:\.(\d{1,}))?"

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

if (!($version -match $versionRegex)) {
  throw "Version did not match the pattern 'major' or 'major.minor'"
}

$matchedVersion = $version | Select-String -Pattern $versionRegex
$major = $matchedVersion.matches.groups[1].value
$minor = $matchedVersion.matches.groups[2].value

if ($create_release) {
  InvokeAndCheckExit "git fetch origin"

  $branch_name = "release-$major"
  if (!($minor -eq "")) {
    $branch_name = "release-$major-$minor"
  }

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

}
