
<#

.DESCRIPTION
    Download and install Google Chrome Enterprise

.NOTES
    Filename: Install-Chrome.ps1
    Version : 22.05.24.01
    Author  : Jeremy Thurgood (DWT)

.LINK
    https://raw.githubusercontent.com/jwthurgood/garytown/master/OSD/CloudOSD/Install-Chrome.ps1
    

#> 


## Set the script execution policy for this process
Try { Set-ExecutionPolicy -ExecutionPolicy 'ByPass' -Scope 'Process' -Force -ErrorAction 'SilentlyContinue'
    } Catch {}


$ScriptName = "Install-Chrome"
$ScriptVersion = "22.05.24.01"

$LogFolder = "C:\Windows\Logs\Software"
$LogFile = "$LogFolder\GoogleChromeEnterprise_$(Get-Date -format yyyy-MM-dd-HHmm).log"

# Create Log folders if they do not exist
if (!(Test-Path -path $LogFolder)){$Null = new-item -Path $LogFolder -ItemType Directory -Force}





function CMTraceLog {
         [CmdletBinding()]
    Param (
		    [Parameter(Mandatory=$false)]
		    $Message,
		    [Parameter(Mandatory=$false)]
		    $ErrorMessage,
		    [Parameter(Mandatory=$false)]
		    $Component = "$ComponentText",
		    [Parameter(Mandatory=$false)]
		    [int]$Type,
		    [Parameter(Mandatory=$true)]
		    $LogFile = "$LogFolder\$($MyInvocation.MyCommand.Name)_$(Get-Date -format yyyy-MM-dd-HHmm).log"
	    )
    <#
    Type: 1 = Normal, 2 = Warning (yellow), 3 = Error (red)
    #>
	    $Time = Get-Date -Format "HH:mm:ss.ffffff"
	    $Date = Get-Date -Format "MM-dd-yyyy"
	    if ($ErrorMessage -ne $null) {$Type = 3}
	    if ($Component -eq $null) {$Component = " "}
	    if ($Type -eq $null) {$Type = 1}
	    $LogMessage = "<![LOG[$Message $ErrorMessage" + "]LOG]!><time=`"$Time`" date=`"$Date`" component=`"$Component`" context=`"`" type=`"$Type`" thread=`"`" file=`"`">"
	    $LogMessage.Replace("`0","") | Out-File -Append -Encoding UTF8 -FilePath $LogFile
    }





CMTraceLog -Message  "--------------------------------------------------------" -Type 1 -LogFile $LogFile
CMTraceLog -Message  "Running Script: $ScriptName | Version: $ScriptVersion   " -Type 1 -LogFile $LogFile
CMTraceLog -Message  "--------------------------------------------------------" -Type 1 -LogFile $LogFile




Write-Host 'Please allow several minutes for the install to complete. '
CMTraceLog -Message "Please allow several minutes for the install to complete" -Type 1 -LogFile $LogFile

# Install Google Chrome x64 on 64-Bit systems? $True or $False
$Installx64 = $True

# Define the temporary location to cache the installer.
$TempDirectory = "$ENV:Temp\Chrome"

# Run the script silently, $True or $False
$RunScriptSilent = $True

# Set the system architecture as a value.
$OSArchitecture = (Get-WmiObject Win32_OperatingSystem).OSArchitecture

# Exit if the script was not run with Administrator priveleges
$User = New-Object Security.Principal.WindowsPrincipal( [Security.Principal.WindowsIdentity]::GetCurrent() )
if (-not $User.IsInRole( [Security.Principal.WindowsBuiltInRole]::Administrator )) {
	Write-Host 'Please run again with Administrator privileges.' -ForegroundColor Red
    CMTraceLog -Message "Please run again with Administrator privileges." -Type 3 -LogFile $LogFile
    if ($RunScriptSilent -NE $True){
        Read-Host 'Press [Enter] to exit'
    }
    exit
}


Function Download-Chrome {
    Write-Host 'Downloading Google Chrome... ' -NoNewLine
    CMTraceLog -Message "Downloading Google Chrome..." -Type 1 -LogFile $LogFile

    # Test internet connection
    if (Test-Connection google.com -Count 3 -Quiet) {
		if ($OSArchitecture -eq "64-Bit" -and $Installx64 -eq $True){
			$Link = 'http://dl.google.com/edgedl/chrome/install/GoogleChromeStandaloneEnterprise64.msi'
		} ELSE {
			$Link = 'http://dl.google.com/edgedl/chrome/install/GoogleChromeStandaloneEnterprise.msi'
		}
    

        # Download the installer from Google
        try {
	        New-Item -ItemType Directory "$TempDirectory" -Force | Out-Null
	        (New-Object System.Net.WebClient).DownloadFile($Link, "$TempDirectory\Chrome.msi")
            Write-Host 'Success!' -ForegroundColor Green
            CMTraceLog -Message "Success!" -Type 1 -LogFile $LogFile

        } catch {
	        Write-Host 'Failed. There was a problem with the download.' -ForegroundColor Red
            CMTraceLog -Message "Failed. There was a problem with the download." -Type 3 -LogFile $LogFile
            if ($RunScriptSilent -NE $True){
                Read-Host 'Press [Enter] to exit'
            }
	        exit
        }
    } else {
        Write-Host "Failed. Unable to connect to Google's servers." -ForegroundColor Red
        CMTraceLog -Message "Failed. Unable to connect to Google's servers" -Type 3 -LogFile $LogFile
        if ($RunScriptSilent -NE $True){
            Read-Host 'Press [Enter] to exit'
        }
	    exit
    }
}

Function Install-Chrome {
    Write-Host 'Installing Chrome... ' -NoNewline
    CMTraceLog -Message "Installing Chrome..." -Type 1 -LogFile $LogFile

    # Install Chrome
    $ChromeMSI = """$TempDirectory\Chrome.msi"""
	$ExitCode = (Start-Process -filepath msiexec -argumentlist "/i $ChromeMSI /qn /norestart" -Wait -PassThru).ExitCode
    
    if ($ExitCode -eq 0) {
        Write-Host 'Success!' -ForegroundColor Green
        CMTraceLog -Message "Success!" -Type 1 -LogFile $LogFile
    } else {
        Write-Host "Failed. There was a problem installing Google Chrome. MsiExec returned exit code $ExitCode." -ForegroundColor Red
        CMTraceLog -Message "Failed. There was a problem installing Google Chrome. MsiExec returned exit code $ExitCode." -Type 3 -LogFile $LogFile
        Clean-Up
        if ($RunScriptSilent -NE $True){
            Read-Host 'Press [Enter] to exit'
        }
	    exit
    }
}

Function Clean-Up {
    Write-Host 'Removing Chrome installer... ' -NoNewline
    CMTraceLog -Message "Removing Chrome installer..." -Type 1 -LogFile $LogFile

    try {
        # Remove the installer
        Remove-Item "$TempDirectory\Chrome.msi" -ErrorAction Stop
        Write-Host 'Success!' -ForegroundColor Green
        CMTraceLog -Message "Success!" -Type 1 -LogFile $LogFile
    } catch {
        Write-Host "Failed. You will have to remove the installer yourself from $TempDirectory\." -ForegroundColor Yellow
        CMTraceLog -Message "Failed. You will have to remove the installer yourself from $TempDirectory\." -Type 2 -LogFile $LogFile
    }
}



Download-Chrome
Install-Chrome
Clean-Up



CMTraceLog -Message  "--------------------------------------------------------" -Type 1 -LogFile $LogFile
CMTraceLog -Message  "                       Finished                         " -Type 1 -LogFile $LogFile
CMTraceLog -Message  "--------------------------------------------------------" -Type 1 -LogFile $LogFile



if ($RunScriptSilent -NE $True){
    Read-Host 'Install complete! Press [Enter] to exit'
}