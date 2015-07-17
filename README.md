# Scan-Network
Powershell Function to Scan a Network to determine if hosts are up, ports are open, ...

### Example Command
    .\Scan-Network.ps1 -ipInput 192.168.1.1-255 -portInput topTcpPorts.txt -connTimeout 100
	
#### ipInput
 + null: all IPs in current subnet will be scanned
 + ip address: that specific ip address will be scanned
 + ip range: ips in the range will be scanned, currently only accepts range in this format xxx.xxx.xxx.xxx-yyy

#### portInput
 + null: port 22 (ssh) will be scanned 
 + port: that specific port address will be scanned
 + port range: ports in the range will be scanned, currently only accepts range in this format x-y (e.g. 1-100)
 + topTcpPorts.txt: will scan the ports listed in topTcpPorts.txt

#### connTimeout
 + null: default connection timeout is 300 ms
 + number: that number will be used as the connection timeout in ms.  Setting to 50 on a LAN should help you find open ports quickly. 
 
#### Debug
 Allows use of the -debug switch which will show all failed connections as well