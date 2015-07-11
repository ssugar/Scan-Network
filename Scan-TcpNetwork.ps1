param(
  $ipInput,
  $portInput
)
switch -wildcard ($ipInput)
{
    $null
    {
        $netcfg = Get-NetIPConfiguration
        $gateway = $netcfg.IPv4DefaultGateway.NextHop
        $segments = $gateway.Split(".")
        $ipsToScan = @()
        $x = 1
        while($x -lt 255)
        {
            $ipToAdd = $segments[0] + "." + $segments[1] + "." + $segments[2] + "." + $x
            $ipsToScan += $ipToAdd
            $x += 1
        }

    }
    "*-*"
    {
        $segments = $ipInput.Split(".")
        $toScan = $segments[3].Split("-")
        $startScan = [int]$toScan[0]
        $endScan = [int]$toScan[1]
        $ipsToScan = @()
        $x = $startScan
        while($x -lt $endScan + 1)
        {
          $ipToAdd = $segments[0] + "." + $segments[1] + "." + $segments[2] + "." + $x
          $ipsToScan += $ipToAdd
          $x += 1
        }
    }
    default
    {
        $ipsToScan = @()
        $ipsToScan += $ipInput
    }
}


if($portInput -ne $null)
{
    $portToQuery = [int]$portInput
}
else
{
    $portToQuery = 22
}


foreach($ip in $ipsToScan)
{
  #$tncoutput = tnc $ip -Port $portToQuery
  $portCheckOutput = New-Object System.Net.Sockets.TcpClient
  $portCheckOutput.BeginConnect($ip, $portToQuery, $null, $null) | Out-Null
  $Timeout = (Get-Date).AddMilliseconds(300)
  While (!$portCheckOutput.Connected -and (Get-Date) -lt $Timeout){Sleep -Milliseconds 50}
  write-host $ip "test result for port" $portToQuery "was" $portCheckOutput.Connected
  $portCheckOutput.Close()
}