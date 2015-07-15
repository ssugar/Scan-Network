param(
  $ipInput,
  $portInput,
  $connTimeout=300,
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
  "topTcpPorts.txt"
  {
    $portsToQuery = @()
    $file = Get-Content .\topTcpPorts.txt
    $lines = $file.split([Environment]::NewLine)
    foreach($line in $lines)
    {
        if($line -match "Service Port")
        {
          #discarding header
        }
        else
        {
            $port = $line.split(" ")
            $portsToQuery += [int]$port[1]
        }
    }
  }
  default
  {
    $portsToQuery = @()
    $portsToQuery += $portInput
  }
}

#taken from http://poshcode.org/2763
function Get-MacFromIP($IPAddress)
{
    $sign = @"
    using System;
    using System.Collections.Generic;
    using System.Text;
    using System.Net;
    using System.Net.NetworkInformation;
    using System.Runtime.InteropServices;
     
    public static class NetUtils
    {
        [System.Runtime.InteropServices.DllImport("iphlpapi.dll", ExactSpelling = true)]
        static extern int SendARP(int DestIP, int SrcIP, byte[] pMacAddr, ref int PhyAddrLen);
     
        public static string GetMacAddress(String addr)
        {
            try
                    {                  
                        IPAddress IPaddr = IPAddress.Parse(addr);
                     
                        byte[] mac = new byte[6];
                       
                        int L = 6;
                       
                        SendARP(BitConverter.ToInt32(IPaddr.GetAddressBytes(), 0), 0, mac, ref L);
                       
                        String macAddr = BitConverter.ToString(mac, 0, L);
                       
                        return (macAddr.Replace('-',':'));
                    }
     
                    catch (Exception ex)
                    {
                        return (ex.Message);              
                    }
        }
    }
"@
     
    $type = Add-Type -TypeDefinition $sign -Language CSharp -PassThru
    $type::GetMacAddress($IPAddress)
}

function pingSweep($ipsToScan, $connTimeout, $onlyTrueFlag)
{
    foreach($ip in $ipsToScan)
    {
        $Ping = New-Object System.Net.NetworkInformation.Ping 
        $reply = $Ping.Send($ip,$connTimeout) 
        Write-Debug $reply 
        If ($onlyTrueFlag -eq 1 -AND $reply.Status -eq "Success")  
        { 
            $mac = Get-MacFromIP $ip
            Write-Host $ip "host up with MAC:" $mac 
        } 
        elseif($onlyTrueFlag -eq 0 -AND $reply.Status -eq "Success")
        { 
            $mac = Get-MacFromIP $ip
            Write-Host $ip "host up with MAC:" $mac 
        }
        elseif($reply.Status -eq "TimedOut" -and $onlyTrueFlag -eq 0)
        {
            Write-Host $ip "host down"
        }   
    }
}

function portSweep($ipsToScan, $portsToQuery, $connTimeout, $onlyTrueFlag)
{
    foreach($ip in $ipsToScan)
    {
        foreach($portToQuery in $portsToQuery)
        {
            $portToQuery = [int]$portToQuery
            $portCheckOutput = New-Object System.Net.Sockets.TcpClient
            $portCheckOutput.BeginConnect($ip, $portToQuery, $null, $null) | Out-Null
            $Timeout = (Get-Date).AddMilliseconds($connTimeout)
            While (!$portCheckOutput.Connected -and (Get-Date) -lt $Timeout){Sleep -Milliseconds 25}
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
}

#Taken from http://myitpath.blogspot.com/2010/03/net-and-netbios-name-resolution.html
function convert-netbiosType([byte]$val) {
 #note netbios type codes are usually in decimal, but .net likes to deal with bytes
 #as integers.
    
 $myval = [int]$val
 switch($myval) {
  0 { return "Workstation" }
  1 { return "Messenger service" }
  3 { return "Messenger" }
  6 { return "RAS" }
  32 { return "File Service" }
  27 { return "Domain Master Browser" }
  28 { return "Domain Controller" }
  29 { return "Master Browser" }
  30 { return "Browser election" }
  31 { return "NetDDE" }
  33 { return "RAS Client" }
  34 { return "Exchange MS mail connector" }
  35 { return "Exchange Store" }
  36 { return "Exchange Directory" }
  48 { return "Modem sharing service Server"}
  49 { return "Modem sharing service Client"}
  67 { return "SMS client remote control" }
  68 { return "SMS client remote transfer" }
  135 { return "Exchange MTA" }
  default { return "unk" }
 }
 
}

#Taken from http://myitpath.blogspot.com/2010/03/net-and-netbios-name-resolution.html
function netBiosSweep($ipsToScan, $connTimeout, $onlyTrueFlag)
{
    foreach($ip in $ipsToScan)
    {
            
        $port=137
        $ipEP = new-object System.Net.IPEndPoint ([system.net.IPAddress]::parse($ip),$port)
        $udpconn = new-Object System.Net.Sockets.UdpClient
        [byte[]] $sendbytes = (0xf4,0x53,00,00,00,01,00,00,00,00,00,00,0x20,0x43,0x4b,0x41,0x41,0x41,0x41,0x41,0x41,0x41,0x41,0x41,0x41,0x41,0x41 ,0x41,0x41,0x41,0x41,0x41,0x41,0x41,0x41,0x41,0x41,0x41,0x41,0x41,0x41,0x41,0x41,0x41,0x41,00,00,0x21,00,01)
        $udpconn.client.receivetimeout=1000
        $bytesSent = $udpconn.Send($sendbytes,50,$ipEP)
        $failed = 0
        try
        {
            $rcvbytes = $udpconn.Receive([ref]$ipEP)
        }
        catch
        {
            $failed = 1
        }
        if ($failed -eq 1 -and $rcvbytes.length -lt 63) 
        {
            if($onlyTrueFlag -eq 0)
            {
                write-host $ip "is not responding to netbios requests"
            }
        }
        else
        {
            [array]$nbnames = $null
            #nbtns query results have a number of returned records field at byte #56 of the returned
            #udp payload.  Read this value to find how many records we have
            $startptr = 56
            $numresults = [int]$rcvbytes[$startptr]
            $startptr++
            $namereclen = 18
            #loop through the number of results and get the names + data
            #  NETBIOS result =  15 byte of name (padded if shorted 0x20)
            #                     1 byte of type
            #                     2 byte of flags
            for ($i = 0; $i -lt $numresults; $i++)
            {
                $nbname = new-object PSObject
                $tempname = ""
                #read the 15 byte name and convert to human readable string
                for ($j = 0; $j -lt $namereclen -3; $j++) 
                {
                    $tempname += [char]$rcvbytes[$startptr + ($i * $namereclen) + $j]
                }
                add-member -input $nbname NoteProperty NetbiosName $tempname
                $rectype = convert-netbiosType $rcvbytes[$startptr + ($i * $namereclen) + 15]
                add-member -input $nbname NoteProperty  RecordType $rectype
                if (($rcvbytes[$startptr + ($i * $namereclen) + 16] -band 128) -eq 128 ) 
                {
                    #in the flags field, only the high order byte of the 2 is used
                    #the left most bit is the Group name flag which can be used for domain
                    #name type identification to differentiate the 0x00 type names
                    $groupflag = 1
                }
                else
                { 
                    $groupflag = 0
                }
                add-member -input $nbname NoteProperty IsGroupType $groupflag
                $nbnames += $nbname
            }
            write-host $ip "netbios names:"
            foreach($nbitem in $nbnames)
            {
                write-host $nbitem
            }
            $rcvbytes = $null
        }
    }
}

pingSweep $ipsToScan $connTimeout $onlyTrueFlag
portSweep $ipsToScan $portsToQuery $connTimeout $onlyTrueFlag
netBiosSweep $ipsToScan $connTimeout $onlyTrueFlag