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
        $udpconn.client.receivetimeout=$connTimeout
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

function netTimeSweep($ipsToScan, $connTimeout)
{
    foreach($ip in $ipsToScan)
    {
        $port=123
        $ipEP = new-object System.Net.IPEndPoint ([system.net.IPAddress]::parse($ip),$port)
        $udpconn = new-Object System.Net.Sockets.UdpClient
        [Byte[]]$sendbytes = ,0 * 48
        $sendbytes[0] = 0x1B #setting first byte with NTP client flag
        $udpconn.client.sendtimeout=$connTimeout
        $udpconn.client.receivetimeout=$connTimeout
        $bytesSent = $udpconn.Send($sendbytes,48,$ipEP)
        $failed = 0
        try
        {
            $rcvbytes = $udpconn.Receive([ref]$ipEP)
            write-host $ip "is responding to NTP requests"
        }
        catch
        {
            write-debug "$ip is not responding to ntp requests"
        }
        $udpconn.Close()
        write-progress -activity "NTP sweep in progress" -status "$ip" -Id 12
    }
    write-progress -activity "NTP sweep completed" -status "Completed" -Completed -Id 12
}

function snmpSweep($ipsToScan, $connTimeout)
{
    foreach($ip in $ipsToScan)
    {
        $port=161
        $ipEP = new-object System.Net.IPEndPoint ([system.net.IPAddress]::parse($ip),$port)
        $udpconn = new-Object System.Net.Sockets.UdpClient
        [Byte[]]$sendbytes = @(48,36,2,1,1,4,6,112,117,98,108,105,99,161,23,2,2,117,6,2,1,0,2,1,0,48,11,48,9,6,5,43,6,1,2,1,5,0)
        $udpconn.client.sendtimeout=$connTimeout
        $udpconn.client.receivetimeout=$connTimeout
        $bytesSent = $udpconn.Send($sendbytes,$sendbytes.Length,$ipEP)
        $failed = 0
        try
        {
            $rcvbytes = $udpconn.Receive([ref]$ipEP)
            write-host $ip "is responding to snmp requests"
        }
        catch
        {
            write-debug "$ip is not responding to snmp requests"
        }
        $udpconn.Close()
        write-progress -activity "SNMP sweep in progress" -status "$ip" -Id 13
    }
    write-progress -activity "SNMP sweep completed" -status "Completed" -Completed -Id 13
}

#taken from http://www.indented.co.uk/2010/02/17/dhcp-discovery/
Function New-DhcpDiscoverPacket
{
  Param(
    [String]$MacAddressString = "AA:BB:CC:DD:EE:FF"
  )
 
  # Generate a Transaction ID for this request
 
  $XID = New-Object Byte[] 4
  $Random = New-Object Random
  $Random.NextBytes($XID)
 
  # Convert the MAC Address String into a Byte Array
 
  # Drop any characters which might be used to delimit the string
  #$MacAddressString = $MacAddressString -Replace "-|:|."
  #$MacAddress = [BitConverter]::GetBytes($MacAddressString,[Globalization.NumberStyles]::HexNumber)
  # Reverse the MAC Address array
 
  # Create the Byte Array
  $DhcpDiscover = New-Object Byte[] 243
 
  # Copy the Transaction ID Bytes into the array
  #[Array]::Copy($XID, 0, $DhcpDiscover, 4, 4)
  
  # Copy the MacAddress Bytes into the array (drop the first 2 bytes,
  # too many bytes returned from UInt64)
  #[Array]::Copy($MACAddress, 2, $DhcpDiscover, 28, 6)
 
  # Set the OP Code to BOOTREQUEST
  $DhcpDiscover[0] = 1
  # Set the Hardware Address Type to Ethernet
  $DhcpDiscover[1] = 1
  # Set the Hardware Address Length (number of bytes)
  $DhcpDiscover[2] = 6
  # Set a "random" number
  $DhcpDiscover[4] = 0
  $DhcpDiscover[5] = 6
  $DhcpDiscover[6] = 6
  $DhcpDiscover[7] = 6
  # Set the Broadcast Flag
  $DhcpDiscover[10] = 0
  # Set the Magic Cookie values
  $DhcpDiscover[236] = 99
  $DhcpDiscover[237] = 130
  $DhcpDiscover[238] = 83
  $DhcpDiscover[239] = 99
  # Set the DHCPDiscover Message Type Option
  $DhcpDiscover[240] = 53
  $DhcpDiscover[241] = 1
  $DhcpDiscover[242] = 1
  
  Return $DhcpDiscover
}

function dhcpSweep($ipsToScan, $connTimeout)
{
#    $UdpSocket = New-Object Net.Sockets.Socket([Net.Sockets.AddressFamily]::InterNetwork,[Net.Sockets.SocketType]::Dgram,[Net.Sockets.ProtocolType]::Udp)
#    $EndPoint = [Net.EndPoint](New-Object Net.IPEndPoint($([Net.IPAddress]::Any, 68)))
#    $UdpSocket.EnableBroadcast = $True
#    $UdpSocket.ExclusiveAddressUse = $False
#    $UdpSocket.SendTimeOut = 1000
#    $UdpSocket.ReceiveTimeOut = 1000
    # Listen on port 68
#    $UdpSocket.Bind($EndPoint)
    
    foreach($ip in $ipsToScan)
    {
        $port=67
        $ipEP = new-object System.Net.IPEndPoint ([system.net.IPAddress]::parse($ip),$port)
        $udpconn = new-Object System.Net.Sockets.UdpClient
        [Byte[]]$sendbytes = New-DhcpDiscoverPacket
        $udpconn.client.sendtimeout=$connTimeout
        $udpconn.client.receivetimeout=1000
        write-host $sendbytes
        $bytesSent = $udpconn.Send($sendbytes,$sendbytes.Length,$ipEP)
        $failed = 0
        try
        {
            $EndPoint = [Net.EndPoint](New-Object Net.IPEndPoint($([Net.IPAddress]::Any, 68)))
            #Receive Buffer
            #$ReceiveBuffer = New-Object Byte[] 1024
            $BytesReceived = $udpconn.Receive([Ref]$EndPoint)
            write-host $ip "is responding to dhcp requests"
        }
        catch
        {
            $ErrorMessage = $_.Exception.Message
            write-host "$ip is not responding to dhcp requests $ErrorMessage"
        }
        $udpconn.Close()
        write-progress -activity "DHCP sweep in progress" -status "$ip" -Id 13
    }
    write-progress -activity "DHCP sweep completed" -status "Completed" -Completed -Id 13
    #$UdpSocket.Close()
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
    netTimeSweep $ipsToScan $connTimeout
    snmpSweep $ipsToScan $connTimeout
    #dhcpSweep $ipsToScan $connTimeout
    #dnsSweep $ipsToScan $connTimeout
}