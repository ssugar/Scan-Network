param(
  $ipInput,
  $portInput,
  $onlyTrueFlag=0
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

switch -wildcard ($portInput)
{
  $null
  {
    $portsToQuery = @()
    $portsToQuery += 22
  }
  "*-*"
  {
    $portsToQuery = @()
    $ports = $portInput.split("-")
    $startPort = [int]$ports[0]
    $endPort = [int]$ports[1]
    $x = $startPort
    while($x -lt $endPort + 1)
    {
        $portsToQuery += $x
        $x += 1
    }
  }
  default
  {
    $portsToQuery = @()
    $portsToQuery += $portInput
  }
}

foreach($portToQuery in $portsToQuery)
{
    $portToQuery = [int]$portToQuery
    foreach($ip in $ipsToScan)
    {
      #$tncoutput = tnc $ip -Port $portToQuery
      $portCheckOutput = New-Object System.Net.Sockets.TcpClient
      $portCheckOutput.BeginConnect($ip, $portToQuery, $null, $null) | Out-Null
      $Timeout = (Get-Date).AddMilliseconds(300)
      While (!$portCheckOutput.Connected -and (Get-Date) -lt $Timeout){Sleep -Milliseconds 50}
      if($onlyTrueFlag -eq 1 -AND $portCheckOutput.Connected -eq $true)
      {
        write-host $ip "test result for port" $portToQuery "was" $portCheckOutput.Connected
      }
      elseif($onlyTrueFlag -eq 0)
      {
        write-host $ip "test result for port" $portToQuery "was" $portCheckOutput.Connected
      }

      $portCheckOutput.Close()
    }
}