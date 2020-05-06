param(
  [string] $command,
  [string] $message,
  [switch] $assertExactMatch,
  [switch] $assertPartialMatch,
  [switch] $assertPass,
  [switch] $assertFail
)

$output = Invoke-Expression "$command 2>&1"

if (!($LastExitCode -eq 0) -and $assertPass) {
  Write-Output $output
  throw "Command ran successfully, which was unexpected."
}
if ($LastExitCode -eq 0 -and $assertFail) {
  Write-Output $output
  throw "Command ran unsuccessfully, which was unexpected."
}

if (!("$output" -eq "$message") -and $assertExactMatch) {
  throw "Command output did not contain: $message. Was $output"
}

if (!("$output" -Match "$message") -and $assertPartialMatch) {
  throw "Command output did not contain: $message. Was $output"
}
