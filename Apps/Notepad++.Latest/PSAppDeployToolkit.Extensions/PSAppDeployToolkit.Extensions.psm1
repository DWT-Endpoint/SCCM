<#

.SYNOPSIS
PSAppDeployToolkit.Extensions - Provides the ability to extend and customize the toolkit by adding your own functions that can be re-used.

.DESCRIPTION
This module is a template that allows you to extend the toolkit with your own custom functions.

This module is imported by the Invoke-AppDeployToolkit.ps1 script which is used when installing or uninstalling an application.

#>

##*===============================================
##* MARK: MODULE GLOBAL SETUP
##*===============================================

# Set strict error handling across entire module.
$ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
$ProgressPreference = [System.Management.Automation.ActionPreference]::SilentlyContinue
Set-StrictMode -Version 1


# Import Variables from ADTSession
$DirFiles				= (Get-ADTSession).DirFiles
$DirSupportFiles		= (Get-ADTSession).DirSupportFiles
$InstallName			= (Get-ADTSession).InstallName
$InstallTitle			= (Get-ADTSession).InstallTitle
$AppProcessesToClose	= (Get-ADTSession).AppProcessesToClose


##*===============================================
##* MARK: FUNCTION LISTINGS
##*===============================================

function New-ADTExampleFunction
{
    <#
    .SYNOPSIS
        Basis for a new PSAppDeployToolkit extension function.

    .DESCRIPTION
        This function serves as the basis for a new PSAppDeployToolkit extension function.

    .INPUTS
        None

        You cannot pipe objects to this function.

    .OUTPUTS
        None

        This function does not return any output.

    .EXAMPLE
        New-ADTExampleFunction

        Invokes the New-ADTExampleFunction function and returns any output.
    #>

    [CmdletBinding()]
    param
    (
    )

    begin
    {
        # Initialize function.
        Initialize-ADTFunction -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState
    }

    process
    {
        try
        {
            try
            {
            }
            catch
            {
                # Re-writing the ErrorRecord with Write-Error ensures the correct PositionMessage is used.
                Write-Error -ErrorRecord $_
            }
        }
        catch
        {
            # Process the caught error, log it and throw depending on the specified ErrorAction.
            Invoke-ADTFunctionErrorHandler -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState -ErrorRecord $_
        }
    }

    end
    {
        # Finalize function.
        Complete-ADTFunction -Cmdlet $PSCmdlet
    }
}
#endregion


function Get-ADTRunningProcessesToClose
{
    <#

    .SYNOPSIS
    Gets the processes that are running from a custom list of process objects and also adds a property called ProcessDescription.

    .DESCRIPTION
    Gets the processes that are running from a custom list of process objects and also adds a property called ProcessDescription.

    .PARAMETER ProcessObjects
    Custom object containing the process objects to search for.

    .INPUTS
    None. You cannot pipe objects to this function.

    .OUTPUTS
    System.Diagnostics.Process. Returns one or more process objects representing each running process found.

    .EXAMPLE
    Get-ADTRunningProcesses -ProcessObjects $processObjects

    .NOTES
    This is an internal script function and should typically not be called directly.

    .NOTES
    An active ADT session is NOT required to use this function.

    .LINK
    https://psappdeploytoolkit.com

    #>

    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = "This function is appropriately named and we don't need PSScriptAnalyzer telling us otherwise.")]
    [CmdletBinding()]
    [OutputType([System.Diagnostics.Process])]
    param
    (
        [Parameter(Mandatory = $true)]
        [AllowNull()][AllowEmptyCollection()]
        [PSADT.Types.ProcessObject[]]$ProcessObjects
    )
	
	
	# Initialize function.
    Initialize-ADTFunction -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    # Return early if we've received no input.
    if ($null -eq $ProcessObjects)
    {
        return
    }
	


    # Get all running processes and append properties.
    Write-ADTLogEntry -Message "Checking for running applications to close, so we can re-launch them when finished: [$(($ProcessObjects.Name | Select-Object -Unique) -join ',')]"
    $runningProcesses = Get-Process -Name $ProcessObjects.Name -ErrorAction Ignore | & {
        process
        {
            if (!$_.HasExited)
            {
                return $_ | Add-Member -MemberType NoteProperty -Name ProcessDescription -Force -PassThru -Value $(
                    if (![System.String]::IsNullOrWhiteSpace(($objDescription = $ProcessObjects | Where-Object -Property Name -EQ -Value $_.ProcessName | Select-Object -ExpandProperty Description -ErrorAction Ignore)))
                    {
                        # The description of the process provided with the object.
                        $objDescription
                    }
                    elseif ($_.Description)
                    {
                        # If the process already has a description field specified, then use it.
                        $_.Description
                    }
                    else
                    {
                        # Fall back on the process name if no description is provided by the process or as a parameter to the function.
                        $_.ProcessName
                    }
                )
            }
        }
    }

    # Return output if there's any.
    if ($runningProcesses)
    {
        Write-ADTLogEntry -Message "The following processes are running and specified to be closed: [$(($runningProcesses.ProcessName | Select-Object -Unique) -join ',')]."
        return ($runningProcesses | Sort-Object -Property ProcessName)
    }
    Write-ADTLogEntry -Message 'Specified applications are not running.'
	
	
	# Finalize function.
    Complete-ADTFunction -Cmdlet $PSCmdlet
	
} ## End Function




Function Get-FileFromUri 
{
	
	<#

	Function for downloading files from URIs (http,https,ftp,file)
	URIs are tried in order and optionally verified via SHA256 hash
	If no destination is specified, gets the filename and saves to $($adtSession.DirFiles)

	#>
	
	
	
    [cmdletbinding()]
    Param (
        [Parameter(Position=0,Mandatory=$true)]
        [string[]]$Uri,
        [Parameter(Position=1,Mandatory=$false)]
        [AllowEmptyString()]
        [string]$Destination,
        [Parameter(Position=2,Mandatory=$false)]
        [AllowEmptyString()]
        [string]$Sha256
    )
	
	

	
	

	# Initialize function.
   Initialize-ADTFunction -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState
	

	# Get filename from the URI
	$uriFilename = (Split-Path -Path $Uri -Leaf)
	
	# Strip any part of filename after ? (query strings for protected downloads)
	If ($uriFilename -match '\?') 
	{
		$uriFilename = $uriFilename.Substring(0, $uriFilename.IndexOf('?'))    
	}
	
	

    If (-not ($Destination)) 
	{
			          
        $Destination = ($DirSupportFiles + '\' + $uriFilename)
    } 



    If (-not (Split-Path -Path $Destination -IsAbsolute)) 
	{
        throw ('Destination invalid; an abolsute path is required')
    }
    
    # Force TLS1.2 seems to help with some websites
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    # Speeds up Invoke-WebRequest when downloading files
    $ProgressPreference = 'SilentlyContinue'

    $uriCount = 0
	$dlSuccess = $false
    do 
	{
        If (-not ($Uri[$uriCount]) ) 
		{
				Write-ADTLogEntry -Message ('No more URIs to try; cannot download ' + $uriFilename)
				return ($false)
        }
        
        Try 
		{
            Write-ADTLogEntry -Message ('Trying to download from: ' + $Uri[$uriCount])
            $dlStartTime = Get-Date
            $download = Invoke-WebRequest -Uri $Uri[$uriCount] -OutFile $Destination -UseBasicParsing -ErrorAction 'Continue'

                If ($?) 
				{
                    Write-ADTLogEntry -Message ('Download completed in ' + $((Get-Date).Subtract($dlStartTime).Seconds) + ' second(s)')

                    # Verify SHA256 Hash if provided
                    If ($Sha256) 
					{
                        $DestinationSha256 = (Get-FileHash -Path $Destination -Algorithm 'SHA256')
                        Write-ADTLogEntry -Message ('Checking hash of downloaded file')
                        $hashMatch = ($DestinationSha256.Hash -eq $Sha256)
    
                        If ($hashMatch) 
						{
                            Write-ADTLogEntry -Message ('Downloaded file matached expected hash.')
                            $dlSuccess = $true
                        } 
						else 
						{
                            Write-ADTLogEntry -Message ('Downloaded file did not match expected hash.')
                            Write-ADTLogEntry -Message ('Expected hash was: ' + $Sha256)
                            Write-ADTLogEntry -Message ('Downloaded hash was: ' + $DestinationSha256.Hash)
                            # Delete wrong file to prevent usage of corrupt or malicious file
                            Remove-Item -Path $Destination -Force
                            $dlSuccess = $false
                        }
                    } 
					else 
					{
                        Write-ADTLogEntry -Message ('Download completed successfully. No SHA256 to compare.')
                        $dlSuccess = $true
                    }
                } 
				else 
				{
                    # This else is redundant?
                    Write-ADTLogEntry -Message ('Error with download.')
                    $dlSuccess = $false
                }

        } 
		Catch 
		{
            $download = $_.Exception
            Write-ADTLogEntry -Message ($download)
        }

        $uriCount++
    } until ($dlSuccess -eq $true) # Download is successful
	
    return ($dlSuccess)

	
	# Finalize function.
    Complete-ADTFunction -Cmdlet $PSCmdlet
		
} ## End Function




# Function to get latest download URI from specified version  
Function Get-SnagitLatestBuildUri {
    param (
        $Version = '25'
    )
	
    # Initialize function.
    Initialize-ADTFunction -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState
	
	
	
    
    Write-ADTLogEntry -Message "Querying techsmith for latest minor build that matches major build: [$Version]"

    # Fetch the Latest Build
    $getallversionsUri = "https://www.techsmith.com/api/v/1/products/getallversions/12"

    $updateFeed = Invoke-RestMethod -Uri $getallversionsUri

    $latestVersion = $updateFeed | where {$_.Major -match $Version}| Select-Object -First 1
    
    Write-ADTLogEntry -Message "$latestVersion"

    $latestVersionID = $latestVersion.VersionID
 

    # Fetch downloads available for latest build
    $getversioninfoUri = "https://www.techsmith.com/api/v/1/products/getversioninfo/$latestVersionID"
    
    $latestversioninfo = Invoke-RestMethod -Uri $getversioninfoUri

    $updateXMLRelPath = ($latestversioninfo).AlternateDownloadInformation

    $relativePath = ($updateXMLRelPath).RelativePath | Select-Object -First 1

    $LatestVersionDownloadURI = "http://download.techsmith.com" + $relativePath + "snagit.msi"

    return $LatestVersionDownloadURI
	
	# Finalize function.
    Complete-ADTFunction -Cmdlet $PSCmdlet

} ## End Function



function Start-DWTProcessAsUser 
{
    param (
        [Parameter(Mandatory)]
        [System.String]$FilePath,
        [System.String]$ArgumentList = ""
    )
	

    ## Initialize function.
    Initialize-ADTFunction -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState
	
	
	## Generate a unique GUID for the task name
	$TaskName = [guid]::NewGuid().ToString()


	## Set new priority
	$NewPriority = 0


    ## Get active user session
    $session = (quser | Select-String ">" | ForEach-Object {
        ($_ -split '\s+')[2]
    })

    if (-not $session) {
		Write-ADTLogEntry -Message "No active user session found."
        return
    }

    ## Compose full command
    $fullCmd = if ($ArgumentList) { "'$($FilePath)' $ArgumentList" } else { "'$($FilePath)'" }
	Write-ADTLogEntry -Message "Full Command [$fullCmd]"

    ## Create the scheduled task
    $createCmd = @"
schtasks /create /tn "$TaskName" /tr "$fullCmd" /sc ONCE /st 00:00 /f /ru "INTERACTIVE"
"@

    ## Invoke-Expression $createCmd
	
	schtasks /create /tn "$TaskName" /tr "$fullCmd" /sc ONCE /st 00:00 /f /ru "INTERACTIVE"
	
	Write-ADTLogEntry -Message "Task Created [$createCmd]"
	
	## Get Info about Task
	$Task = Get-ScheduledTask -TaskName $TaskName

	## Record default priority
	$TaskSettings = $Task.Settings
	$OldPriority = $TaskSettings.Priority
	
	## For possible values see https://learn.microsoft.com/en-us/windows/win32/taskschd/tasksettings-priority#remarks
	## 0: Real Time,  1: High,  2: Above Normal,  3: Above Normal,  4: Normal,  5: Normal, 6: Normal, 7: Below Normal, 8: Below Normal,  9: Lowest, 10: Idle
	## Priority level 0 is the highest priority, and priority level 10 is the lowest priority. The default value is 7. Priority levels 7 and 8 are used for background tasks, and priority levels 4, 5, and 6 are used for interactive tasks.
	
	## Set new priority
	$TaskSettings.Priority = $NewPriority
	
	## Update task with new priority
	$TaskLog = Set-ScheduledTask -TaskName $TaskName -TaskPath $Task.TaskPath -Settings $TaskSettings | 
		ft -AutoSize TaskPath, TaskName, @{Name='OldPriority'; Expression = {$OldPriority}}, `
		@{Name='NewPriority'; Expression = {((Get-ScheduledTask -TaskName $TaskName).Settings).Priority}}
	
	## outcome
	Write-ADTLogEntry -Message "Task Priority modified [$TaskLog]"
	

    
	
	## Run the task immediately
    schtasks /run /tn "$TaskName"
	
	Write-ADTLogEntry -Message "Running Task [$TaskName]"

    ## Optional: Wait and then delete the task
    Start-Sleep -Seconds 1
    schtasks /delete /tn "$TaskName" /f
	
	Write-ADTLogEntry -Message "Deleting Task [$TaskName]"
	
	
	## Finalize function.
    Complete-ADTFunction -Cmdlet $PSCmdlet

	
} ## End Function




Function Set-UserFta {
	<#
	
	.SYNOPSIS
		Function to set file association for logged in user
	.DESCRIPTION
		Requires external tool SetUserFTA.exe (should be in SupportFiles subdirectory)
	.PARAMETER Extension
		Name of extension.  Example: '.pdf'
	.PARAMETER ApplicationId
		The application ID.  Example: 'PowerPDF.Document'
	.PARAMETER Ask
		Switch to set whether or not to ask user to change extension handler.
	.INPUTS
		None
		You cannot pipe objects to this function.
	.OUTPUTS
		None
		This function does not generate any output.
	.EXAMPLE
		Set-UserFta -Extension '.pdf' -ApplicationId 'PowerPDF.Document' -Ask:$true
	.NOTES
		This is an internal script function and should typically not be called directly.
		Author: Leonardo Franco Maragna
		Part of Toast Notification Extension
	.LINK
		https://psappdeploytoolkit.com

	#>
	
    [CmdletBinding()]
    param (
        [Parameter(Position=0,Mandatory=$true,ValueFromPipeline=$true)]
        [string]$Extension,
        [Parameter(Position=1,Mandatory=$true,ValueFromPipeline=$true)]
        [string]$ApplicationId,
        [Parameter(Mandatory=$false)]
        [switch]$Ask
            
    )
	
	# Initialize function.
    Initialize-ADTFunction -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState
        
    begin {
        $progSetUserFTA = "$($DirSupportFiles)\SetUserFTA.exe"
        If (-not (Test-Path -Path $progSetUserFTA)) {
            Write-ADTLogEntry -Message 'ERROR: Unable to set file type associaion; SetUserFTA was not found.'
            return ('Error: ' + $progSetUserFTA + ' not found.')
        }
    }
        
    process {
        If ($Ask) {
            $promptSetFTA = (Show-ADTInstallationPrompt -Message ('Would you like to set ' + $appName + ' as the default program for ' + $Extension + '?') -Icon 'Question' -ButtonLeftText 'No' -ButtonRightText 'Yes' -Timeout 60 -NoExitOnTimeout)
            If ($promptSetFTA -notlike 'Yes') {
                Write-ADTLogEntry -Message ('User selected "No" or timeout on the FTA prompt.')
                return ($false)
            }
        }
        Write-ADTLogEntry -Message ($appName + ' set as the default program for ' + $Extension + ' for ' + ($CurrentLoggedOnUserSession.NTAccount))
        Show-ADTBalloonTip -BalloonTipText ($appName + ' set as the default program for ' + $Extension) -BalloonTipIcon 'Info'
        ## Execute-ProcessAsUser -Path $progSetUserFTA -Parameters ($Extension + ' ' + $ApplicationId) -Wait
		
		## Workaround for above, until fixed in PSADT 4.1
		Start-ADTProcessAsUser -FilePath "cmd.exe" -ArgumentList "/C `"$progSetUserFTA`" $Extension + ' ' + $ApplicationId" -HideWindow
    }
	
	# Finalize function.
    Complete-ADTFunction -Cmdlet $PSCmdlet
     
} ## End Function




function Start-DownloadFile {
    param(
        [parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$URL,

        [parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Name
    )
	
	
	# Initialize function.
    Initialize-ADTFunction -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState
	

        # Construct WebClient object
        $WebClient = New-Object -TypeName System.Net.WebClient

        # Create path if it doesn't exist
        if (-not(Test-Path -Path $Path)) {
            New-Item -Path $Path -ItemType Directory -Force | Out-Null
        }

        # Start download of file
        $WebClient.DownloadFile($URL, (Join-Path -Path $Path -ChildPath $Name))

        # Dispose of the WebClient object
        $WebClient.Dispose()

	
	# Finalize function.
    Complete-ADTFunction -Cmdlet $PSCmdlet
	
} ## End Function




function Get-ExeFileInfo
{
	<#
	.SYNOPSIS
		Retrieves detailed file information from an EXE file.
	
	.DESCRIPTION
		This script uses PowerShell to extract metadata such as:
		- File Version
		- Product Version
		- Company Name
		- Product Name
		- Description
		- File Size
		- Creation / Modification Dates
	
	.PARAMETER FilePath
		Full path to the EXE file.
	
	.EXAMPLE
		$FileInfo = Get-ExeFileInfo -FilePath "\\dwt.com\dfs01\AdminStudio\WorkspaceApps\ABBYY\Fine_Reader_v16\Files\Setup.exe"
	#>

    [CmdletBinding()]
	param
	(
		[Parameter(Mandatory = $true)]
		[string]$FilePath
	)

    begin
    {
        # Initialize function.
        Initialize-ADTFunction -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState
    }

    process
    {
        try
        {
            try
            {
				# Validate file existence
				if (-not (Test-Path -Path $FilePath -PathType Leaf))
				{
					throw "File not found: $FilePath"
				}
				
				# Get file version info
				$fileInfo = Get-Item -Path $FilePath
				$versionInfo = $fileInfo.VersionInfo
			
				# Output details in a structured way
				[PSCustomObject]@{
					FileName       = $fileInfo.Name
					FullPath       = $fileInfo.FullName
					FileSizeKB     = [math]::Round($fileInfo.Length / 1KB, 2)
					FileVersion    = $versionInfo.FileVersion
					ProductVersion = $versionInfo.ProductVersion
					ProductName    = $versionInfo.ProductName
					CompanyName    = $versionInfo.CompanyName
					Description    = $versionInfo.FileDescription
					Language       = $versionInfo.Language
					Created        = $fileInfo.CreationTime
					Modified       = $fileInfo.LastWriteTime
				}
            }
            catch
            {
                # Re-writing the ErrorRecord with Write-Error ensures the correct PositionMessage is used.
                Write-Error -ErrorRecord $_
            }
        }
        catch
        {
            # Process the caught error, log it and throw depending on the specified ErrorAction.
            Invoke-ADTFunctionErrorHandler -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState -ErrorRecord $_
        }
    }

    end
    {
        # Finalize function.
        Complete-ADTFunction -Cmdlet $PSCmdlet
    }
}
#endregion




function Install-Fonts
{
	<#
	.SYNOPSIS
		Install fonts from specified directory
	
	.DESCRIPTION
		This script uses PowerShell to extract metadata such as:
		- File Version
		- Product Version
		- Company Name
		- Product Name
		- Description
		- File Size
		- Creation / Modification Dates
	
	.PARAMETER FontFolder
		Name of folder containing fonts to install
	
	.EXAMPLE
		Install-Fonts -FontFolder "AptosFonts"
	#>
	
	[CmdletBinding()]
	param
	(
		[Parameter(Mandatory=$true)]
		$FontFolder = $null
	)


    begin
    {
        # Initialize function.
        Initialize-ADTFunction -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState
    }

    process
    {
        try
        {
            try
            {
				$WorkingPath = "$($DirFiles)\$FontFolder"
				
				$RegKey = "HKLM:\SOFTWARE\DWT\Fonts"
				if (-not(Test-Path -Path $RegKey)) { New-Item -Path $RegKey -Force | Out-Null }

				## Copy fonts to C:\Windows\Fonts
				ROBOCOPY "$WorkingPath" "$env:windir\Fonts" /B /MIR /XX /R:2 /W:2 | Out-String | Write-ADTLogEntry
				
				$fileTypes = @("*.ttf","*.otf","*.fnt","*.ttc")
				$fontsToInstall = Get-ChildItem -path "$WorkingPath" -Include $fileTypes -Recurse
				
				$fontCount = $($FontsToInstall).Count
				
				$currentDateTime = Get-Date -Format "M/dd/yyyy hh:mm:ss tt"
				New-ItemProperty -Path $RegKey -Name "_$($FontFolder)"  -Value "Count: $($FontCount)" -PropertyType "String" -Force | Out-Null 
				
				Write-ADTLogEntry -Message "Font Count [$($fontCount)]"
				
				$FontCounter = 1
				
				foreach($FontFile in $fontsToInstall)
				{
					try
					{
						$BaseName = $($FontFile).BaseName
						$FontName = $($FontFile).Name
						$FontType = (($FontName).Split('.')[-1])
						$FontExtension = (($FontName).Split('.')[-1])
				
							switch -exact ($FontExtension) {
								'ttf' {
									$RegFontName = $BaseName + ' (TrueType)'
								}
								'otf' {
									$RegFontName = $BaseName + ' (OpenType)'
								}
								'fnt' {
									$RegFontName = $BaseName + ' (FontFile)'
								}
								'ttc' {
									$RegFontName = $BaseName + ' (TrueTypeCollection)'
								}
				
							} # End Switch
							
				
						## Copy-Item -Path "$WorkingPath\$($FontFile.Name)" -Destination "$env:windir\Fonts" -Force -PassThru -ErrorAction Stop -verbose
						Write-ADTLogEntry -Message "Installing font [$($FontCounter)] of [$($fontCount)] : [$($FontName)]"
						
						## Write font to Font Registry so Windows knows about it
						New-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts" -Name $RegFontName -PropertyType String -Value $FontName -Force | Out-Null 
						
						## Write font to DWT registry for tracking
						$currentDateTime = Get-Date -Format "M/dd/yyyy hh:mm:ss:fff tt" ## could add fff (for milliseconds - example: M/dd/yyyy hh:mm:ss:fff tt)
						New-ItemProperty -Path $RegKey -Name "$($FontFolder) -- [Font: $($FontCounter)]"  -Value "$($RegFontName) -- $($FontName) -- $($currentDateTime)" -PropertyType "String" -Force | Out-Null 
						
					}catch{
						Write-Error -ErrorRecord $_
					}
					
					## Increment Font Counter
					$FontCounter++
					## Pause for 0.5 seconds to allow proper sorting in registry
					## Start-Sleep -Milliseconds 500 
				}

            }
            catch
            {
                # Re-writing the ErrorRecord with Write-Error ensures the correct PositionMessage is used.
                Write-Error -ErrorRecord $_
            }
        }
        catch
        {
            # Process the caught error, log it and throw depending on the specified ErrorAction.
            Invoke-ADTFunctionErrorHandler -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState -ErrorRecord $_
        }
    }

    end
    {
        # Finalize function.
        Complete-ADTFunction -Cmdlet $PSCmdlet
    }


}
#endregion





##*===============================================
##* MARK: SCRIPT BODY
##*===============================================

# Announce successful importation of module.
Write-ADTLogEntry -Message "Module [$($MyInvocation.MyCommand.ScriptBlock.Module.Name)] imported successfully." -ScriptSection Initialization