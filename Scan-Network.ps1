param(
  $ipInput,
  $portInput,
  $connTimeout=300,
  $updateOuiList=0,
  $updatePortList=0
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

function vendorLookup([string]$mac)
{
    $macSegments = $mac.Split(":")
    $targetString = $macSegments[0] + "-" + $macSegments[1] + "-" + $macSegments[2]
    $manufacturer = $fileContent | Select-String $targetString -Context 0,0
    [string]$manName = $manufacturer.ToString()
    $manNameSegments = $manName -split "`t"
    return $manNameSegments[2]
}

function pingSweep($ipsToScan, $connTimeout)
{
    $fileContent = Get-Content -Path ".\vendorlist.txt"
    foreach($ip in $ipsToScan)
    {
        $Ping = New-Object System.Net.NetworkInformation.Ping 
        $reply = $Ping.Send($ip,$connTimeout) 
        If ($reply.Status -eq "Success")  
        { 
            $mac = Get-MacFromIP $ip
            $mac = [string]$mac
            $vendorName = vendorLookup $mac
            Write-Host $ip "host up with MAC:" $mac "(" $vendorName ")"
        } 
        else
        {
            Write-debug "$ip host down"
        }
        write-progress -activity "Ping sweep in progress" -status "$ip" -Id 9
    }
    write-progress -activity "Ping sweep completed" -status "completed" -completed -Id 9
}

function portLookup([int]$port)
{
    [string]$portString = [string]$port
    #add word boundry regex \b to each side of the port to get an exact match
    $selectString = "\b" + $port + "\b"
    $portName = $portFileContent | Select-String $selectString -Context 0,0
    [string]$portName = [string]$portName
    $portNameSegments = $portName.Split(" ")
    return $portNameSegments[0]
}

function portSweep($ipsToScan, $portsToQuery, $connTimeout)
{
    $portFileContent = Get-Content -Path ".\topTcpPorts.txt"
    foreach($ip in $ipsToScan)
    {
        foreach($portToQuery in $portsToQuery)
        {
            $portToQuery = [int]$portToQuery
            $portCheckOutput = New-Object System.Net.Sockets.TcpClient
            $portCheckOutput.BeginConnect($ip, $portToQuery, $null, $null) | Out-Null
            $Timeout = (Get-Date).AddMilliseconds($connTimeout)
            While (!$portCheckOutput.Connected -and (Get-Date) -lt $Timeout){Sleep -Milliseconds 25}
            if($portCheckOutput.Connected -eq $true)
            {
                $portNameResult = portLookup $portToQuery
                write-host $ip "port" $portToQuery "is open (" $portNameResult ")"
            }
            else
            {
                write-debug "$ip port $portToQuery is closed"
            }
            $portCheckOutput.Close()
            write-progress -activity "Port sweep in progress" -status "$ip $portToQuery" -Id 10
        }
    }
    write-progress -activity "Port sweep completed" -status "completed" -completed -Id 10    
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
function netBiosSweep($ipsToScan, $connTimeout)
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
            write-debug "$ip is not responding to netbios requests"
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
        write-progress -activity "NetBios sweep in progress" -status "$ip" -Id 11
    }
    write-progress -activity "NetBios sweep completed" -status "completed" -completed -Id 11
}

#taken from: chrisjwarwick.wordpress.com 
function netTimeSweep($ipsToScan, $connTimeout)
{
    foreach($ip in $ipsToScan)
    {
        #$StartOfEpoch=New-Object DateTime(1900,1,1,0,0,0,[DateTimeKind]::Utc)   
        $port = 123
        $ipEP = new-object System.Net.IPEndPoint ([system.net.IPAddress]::parse($ip),$port)
        [Byte[]]$NtpData = ,0 * 48
        $NtpData[0] = 0x1B    # NTP Request header in first byte
        $Socket = new-Object System.Net.Sockets.UdpClient
        $Socket.Connect($ip)
        $t1 = Get-Date    # Start of transaction... the clock is ticking..
        $Socket.client.receivetimeout=1000

        $bytesSent = $Socket.Send($NtpData,50,$ipEP)
        $failed = 0
        try
        {
            $rcvbytes = $Socket.Receive([ref]$ipEP)
        }
        catch
        {
            write-host "UDP Receive failed"
        }
        $t4 = Get-Date    # End of transaction time
        $Socket.Close()
        write-host $NtpData
        #$IntPart = [BitConverter]::ToUInt32($NtpData[43..40],0)   # t3
        #$FracPart = [BitConverter]::ToUInt32($NtpData[47..44],0)
        #$t3ms = $IntPart * 1000 + ($FracPart * 1000 / 0x100000000)
        #$IntPart = [BitConverter]::ToUInt32($NtpData[35..32],0)   # t2
        #$FracPart = [BitConverter]::ToUInt32($NtpData[39..36],0)
        #$t2ms = $IntPart * 1000 + ($FracPart * 1000 / 0x100000000)
        #$t1ms = ([TimeZoneInfo]::ConvertTimeToUtc($t1) - $StartOfEpoch).TotalMilliseconds
        #$t4ms = ([TimeZoneInfo]::ConvertTimeToUtc($t4) - $StartOfEpoch).TotalMilliseconds
        #$Offset = (($t2ms - $t1ms) + ($t3ms-$t4ms))/2
        #$StartOfEpoch.AddMilliseconds($t4ms + $Offset).ToLocalTime() 
    }
}


if($updateOuiList -eq 1)
{
    write-host "Downloading/updating the OUI database to the current folder vendorlist.txt, all other non update options ignored.  This can take a while"
    $url = 'http://standards.ieee.org/develop/regauth/oui/oui.txt'
    $outfile = ".\vendorlist.txt"
    Invoke-WebRequest -Uri $url -OutFile $outfile
}
elseif($updatePortList -eq 1)
{
    write-host "Downloading/updating the port list to the current folder fullportlist.txt, all other non update options ignored.  This can take a while"
    $url = 'http://www.iana.org/assignments/service-names-port-numbers/service-names-port-numbers.txt'
    $outfile = ".\fullportlist.txt"
    Invoke-WebRequest -Uri $url -OutFile $outfile
}
else
{
    pingSweep $ipsToScan $connTimeout
    portSweep $ipsToScan $portsToQuery $connTimeout
    netBiosSweep $ipsToScan $connTimeout
#    netTimeSweep $ipsToScan $connTimeout
}