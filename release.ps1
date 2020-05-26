param(
  # The release version
  [string] $version,
  # Workflows (specify only one of these)
  [switch] $create_release,
  [switch] $create_hotfix_release,
  [switch] $mark_released,
  [switch] $list_releases,
  [switch] $backmerge,
  # Optional args
  [string] $hotfix_base_branch,
  [string] $backmerge_branchname,
  [switch] $safe_mode # Skip pushing anything
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
    throw "master contains commits not merged back into $backmerge_branchname. Please fix that before proceeding. $(GetGithubUrl)/compare/master?expand=1&title=Backmerge+from+master+to+develop&body=Backmerge"
  }
}

function GetBranchName() {
  param([string] $version)

  $patchPattern = "^(\d+)(?:\.(\d+))(?:\.(\d+))$"
  $minorPattern = "^(\d+)(?:\.(\d+))$"
  $majorPattern = "^(\d+)$"

  if ($version -Match $patchPattern) {
    $branch_name = $version | Select-String -Pattern $patchPattern | % { "release-$($_.matches.groups[1])-$($_.matches.groups[2])-$($_.matches.groups[3])" }
  }
  elseif ($version -Match $minorPattern) {
    $branch_name = $version | Select-String -Pattern $minorPattern | % { "release-$($_.matches.groups[1])-$($_.matches.groups[2])" }
  }
  elseif ($version -Match $majorPattern) {
    $branch_name = $version | Select-String -Pattern $majorPattern | % { "release-$($_.matches.groups[1])" }
  }
  else {
    throw "Version did not match the pattern 'major' or 'major.minor' or 'major.minor.patch'. Eg. '123.4' instead of 'release-123-4'."
  }

  return $branch_name
}

function GetGithubUrl {
  $output = InvokeAndCheckExit "git remote get-url origin"
  # Not intended to be comprehensive of all possible repo names.
  $remoteRegex = "github.com(?:\/|:)([\w-_]+)\/([\w-_]+)"
  if ($output -Match $remoteRegex) {
    return $output | Select-String -Pattern $remoteRegex | % { "https://github.com/$($_.matches.groups[1])/$($_.matches.groups[2])"}
  } else {
    return $output
  }
}

function Backmerge {
  param([string] $backmerge_branchname)

  $pendingMerges = InvokeAndCheckExit "git diff origin/develop...origin/$($backmerge_branchname)"
  if ($pendingMerges -eq $null) {
    Write-Host "No merge required for develop."
  } else {
    Write-Host -ForegroundColor yellow -NoNewLine "Merge required for develop, please open: "
    Write-Host "$(GetGithubUrl)/compare/$($backmerge_branchname)?expand=1&title=Backmerge+from+$($backmerge_branchname)+to+develop&body=Backmerge"
  }

  # For any hotfix branches
  $allRefs = InvokeAndCheckExit "git ls-remote origin"
  foreach ($branch in $allRefs | Select-String -Pattern "refs\/heads\/(release-\d+(?:-\d+){0,2}$)" | % { "$($_.matches.groups[1])" } )
  {
    $isStaleBranch = InvokeAndCheckExit "git diff origin/$($backmerge_branchname)...origin/$branch"
    $pendingMerges = InvokeAndCheckExit "git diff origin/$branch...origin/$($backmerge_branchname)"
    if ($pendingMerges -eq $null) {
      Write-Host "No merge required for $branch."
    } elseif ($isStaleBranch -eq $null) {
      Write-Host "Ignoring already released branch $branch"
    }
    else {
      Write-Host -ForegroundColor yellow -NoNewLine "Merge required for $branch, please open: "
      Write-Host "$(GetGithubUrl)/compare/$branch...$($backmerge_branchname)?expand=1&title=Backmerge+from+$backmerge_branchname+to+$branch&body=Backmerge"
    }
  }
}

if (!(("$list_releases $create_release $create_hotfix_release $mark_released $backmerge" -split "True").Length -eq 2)) {
  throw "Please specify exactly one of: -list_releases, create_release, create_hotfix_release, mark_released, backmerge."
}

if ($list_releases) {
  GetGithubUrl
  InvokeAndCheckExit "git fetch origin -q"
  $allRefs = InvokeAndCheckExit "git ls-remote origin"
  if (!($Env:CI -eq '1')) {
    Write-Output "Current release branches:"
  }
  foreach ($branch in $allRefs | Select-String -Pattern "refs\/heads\/(release-\d+(?:-\d+){0,2}$)" | % { "$($_.matches.groups[1])" } ) {
    if ((InvokeAndCheckExit "git diff origin/master...origin/$branch") -eq $null) {
      Write-Host -ForegroundColor yellow "No unreleased commits - $branch"
    } else {
      Write-Output "Branch $branch"
    }
  }

  if (!($Env:CI -eq '1')) {
    Write-Output "Last 5 tagged releases:"
  }
  $lastFiveTags = ($allRefs | Select-String -Pattern "refs\/tags\/v(\d+(?:\.\d+){0,2}$)" | % { "$($_.matches.groups[1])" } | Sort-Object -Descending { [Version] "$_.0" } | Select -First 5 | % { "Tag v$_" })
  Write-Output $lastFiveTags
}

if ($create_release) {
  InvokeAndCheckExit "git fetch origin -q"
  CheckForPendingBackmerge "develop"

  if ($version -eq "") {
    throw "No version specified. Please run -list_releases and then pass in a version with -version."
  }
  $branch_name = GetBranchName $version

  if (DoesRefExist "refs/tags/v$version") {
    throw "Tag $version already exists on remote, please delete it and try again"
  }
  if (DoesRefExist "refs/remotes/origin/$branch_name") {
    throw "Branch $branch_name already exists on remote, please delete it and try again"
  }
  if (DoesRefExist "refs/heads/$branch_name") {
    throw "Branch $branch_name already exists locally, please delete it and try again"
  }

  if (!($Env:CI -eq '1')) {
    Write-Host -ForegroundColor yellow "About to create $branch_name. Type OK to continue"
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
  if ($hotfix_base_branch -eq "") {
    throw "Please specify -hotfix_base_branch"
  }
  if ($version -eq "") {
    throw "Please specify -version"
  }

  $hotfix_new_branch = GetBranchName $version

  if (!(DoesRefExist "refs/remotes/origin/$hotfix_base_branch")) {
    throw "Branch $hotfix_base_branch does not exist on remote"
  }
  $pendingMerges = InvokeAndCheckExit "git diff origin/$hotfix_base_branch...origin/master"
  if (!($pendingMerges -eq $null)) {
    throw "Merge required from master into $hotfix_base_branch first."
  }

  if (!($Env:CI -eq '1')) {
    Write-Host -ForegroundColor yellow "About to create $hotfix_new_branch based off of $hotfix_base_branch. Type OK to continue"
    if (!((Read-Host) -ieq 'ok')) {
      throw "Sorry, cannot continue."
    }
  }

  RunWithSafetyCheck "git checkout -q origin/$hotfix_base_branch"
  RunWithSafetyCheck "git checkout -b $hotfix_new_branch"
  RunWithSafetyCheck "git push origin $hotfix_new_branch"
}

if ($mark_released) {
  InvokeAndCheckExit "git fetch origin -q"

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
    Write-Host -ForegroundColor yellow "About to mark $branch_name as released. Type OK to continue"
    if (!((Read-Host) -ieq 'ok')) {
      throw "Sorry, cannot continue."
    }
  }

  if (DoesRefExist "refs/tags/v$version") {
    Write-Output "Tag $version already exists on remote, skipping"
  } else {
    RunWithSafetyCheck "git tag v$version"
    RunWithSafetyCheck "git push origin v$version"
  }

  RunWithSafetyCheck "git push origin HEAD:master"

  if (DoesRefExist "refs/heads/$branch_name") {
    RunWithSafetyCheck "git branch -d $branch_name"
  }

  RunWithSafetyCheck "git push origin -d $branch_name"

  Backmerge "master"
}

if ($backmerge) {
  InvokeAndCheckExit "git fetch origin -q"
  if ($backmerge_branchname -eq "") {
    throw "Please specify `-backmerge_branchname` to base the backmerge off of, such as master or release-123."
  }
  Backmerge $backmerge_branchname
}
