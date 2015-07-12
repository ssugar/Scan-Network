# Scan-TcpNetwork
Powershell Function to Scan a TCP Network to determine if ports are open

### Example Command
    .\Scan-TcpNetwork.ps1 -ipInput 192.168.1.1-255 -portInput topTcpPorts.txt -onlyTruFlag 1 -connTimeout 100
	
#### ipInput
null: all IPs in current subnet will be scanned
ip address: that specific ip address will be scanned
ip range: ips in the range will be scanned, currently only accepts range in this format xxx.xxx.xxx.xxx-yyy

#### portInput
null: port 22 (ssh) will be scanned 
port: that specific port address will be scanned
port range: ports in the range will be scanned, currently only accepts range in this format x-y (e.g. 1-100)
topTcpPorts.txt: will scan the ports listed in topTcpPorts.txt

#### onlyTrueFlag
null or 0: all connection results will be returned
1: only successfuly connection results will be returned

#### connTimeout
null: default connection timeout is 300 ms
number: that number will be used as the connection timeout in ms.  Setting to 50 on a LAN should help you find open ports quickly. 