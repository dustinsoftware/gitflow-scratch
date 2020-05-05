param(
  [string] $command,
  [string] $message
)

function InvokeAndCheckExit {
  param([string] $command)

  $output = Invoke-Expression "$command 2>&1"

  if ($LastExitCode -eq 0) {
    Write-Output $output
    throw "Command ran successfully, which was unexpected."
  }
  if (!($output -Match $message)) {
    throw "Command output did not contain: $message"
  }

  return $output
}

InvokeAndCheckExit $command
