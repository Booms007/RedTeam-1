## This version is being tested in Cobalt Strike 3.2 (4 Apr 2016)
## Author: Gary Butler
## Date: 25 June 2017 1911 GMT
## This version is fully functional. It takes the contents from
## a file and sends them to a Mailslot. The Start-Delivery
## (Main) function requires an input file (-InputFile).

# This section imports libraries from the kernel. The Add-Type
# way of doing this does create files on disk. :(
Add-Type -TypeDefinition @"
	using System;
	using System.Diagnostics;
	using System.Runtime.InteropServices;
	using System.IO;
	using System.Security.Permissions;

	[Flags]
	public enum FileDesiredAccess : uint
	{
	    GenericWrite = 0x40000000,
	}

	[Flags]
	public enum FileShareMode : uint
	{
	    Read = 0x00000001,
	}

	public enum FileCreationDisposition : uint
	{
	    OpenExisting = 3,
	}

	public static class kernel32
	{
		[DllImport("kernel32.dll", CharSet = CharSet.Ansi, SetLastError = true)]
		public static extern bool CloseHandle(
							IntPtr hObject);

		[DllImport("kernel32.dll", CharSet = CharSet.Ansi, SetLastError = true)]
	    [return: MarshalAs(UnmanagedType.Bool)]
	    public static extern bool WriteFile(uint handle,
                            string messageout, int numBytesToWrite, out int numBytesWritten,
                            IntPtr overlapped);

	    [DllImport("kernel32.dll", CharSet = CharSet.Ansi, SetLastError = true)]
	    public static extern uint CreateFile(string fileName,
                            FileDesiredAccess desiredAccess, FileShareMode shareMode,
                            IntPtr securityAttributes,
                            FileCreationDisposition creationDisposition,
                            int flagsAndAttributes, IntPtr hTemplateFile);
	}
"@

# This function returns the handle given by the system to write to
function New-Mail
{
	[CmdletBinding()]
	Param(
		[Parameter(Mandatory = $True, Position = 1)]
			[string]$MailSlotName
		)
	
	try
	{
		$hFile = [kernel32]::CreateFile("\\.\mailslot\$MailSlotName", 1073741824, 1, 0, 3, 0, 0)
	}
	
	catch
	{
		Write-Output "Create File: $PSItem.Exception"
		return $hFile
	}
	
	Write-Host "File Handle is: $hFile."
	Write-Output $hFile
}

# This function uses the handle given by the system to 
# write the contents of the specified file to it.
function Send-Mail
{
	[CmdletBinding()]
	Param (
		[Parameter(Mandatory = $True, Position = 1)]
		[int]$FileHandle,
		[Parameter(Mandatory = $true, Position = 2)]
		[string]$InputFile
	)
	
	$bytesWritten = 0
	$fileLength = (Get-ChildItem $InputFile).Length
#	$buffer = [System.Convert]::ToBase64String(([System.Text.Encoding]::ASCII.GetBytes(($buffer))))
	$buffer = (Get-Content $InputFile)
	
# Attempt to write all bytes of the file to the Mailslot buffer
	if ([kernel32]::WriteFile($FileHandle, $buffer, $fileLength, [ref]$bytesWritten, 0) -ne $true -or $fileLength -ne $bytesWritten)
	{
		Write-Output "Send-Mail Failed."
		[kernel32]::CloseHandle($FileHandle)
	}
	
	Write-Output "Send-Mail Success!"
#	Return $true
}

# This function utilizes the New-Mail and Send-Mail functions
# to send file contents to a mail slot.
function Start-Delivery
{
	[CmdletBinding()]
	Param (
		[Parameter(Mandatory = $false, Position = 1)]
		[string]$MailSlotName = "MailSlotAlpha",
		[Parameter(Mandatory = $true, Position = 2)]
		[string]$InputFile
	)
	
	
	$fh = (New-Mail -MailSlotName $MailSlotName)
	Send-Mail -FileHandle $fh -InputFile $InputFile
	
#	return $true
}