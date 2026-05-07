<#

.SYNOPSIS
PSAppDeployToolkit - This script performs the installation or uninstallation of an application(s).

.DESCRIPTION
- The script is provided as a template to perform an install, uninstall, or repair of an application(s).
- The script either performs an "Install", "Uninstall", or "Repair" deployment type.
- The install deployment type is broken down into 3 main sections/phases: Pre-Install, Install, and Post-Install.

The script imports the PSAppDeployToolkit module which contains the logic and functions required to install or uninstall an application.

.PARAMETER DeploymentType
The type of deployment to perform.

.PARAMETER DeployMode
Specifies whether the installation should be run in Interactive (shows dialogs), Silent (no dialogs), NonInteractive (dialogs without prompts) mode, or Auto (shows dialogs if a user is logged on, device is not in the OOBE, and there's no running apps to close).

Silent mode is automatically set if it is detected that the process is not user interactive, no users are logged on, the device is in Autopilot mode, or there's specified processes to close that are currently running.

.PARAMETER SuppressRebootPassThru
Suppresses the 3010 return code (requires restart) from being passed back to the parent process (e.g. SCCM) if detected from an installation. If 3010 is passed back to SCCM, a reboot prompt will be triggered.

.PARAMETER TerminalServerMode
Changes to "user install mode" and back to "user execute mode" for installing/uninstalling applications for Remote Desktop Session Hosts/Citrix servers.

.PARAMETER DisableLogging
Disables logging to file for the script.

.EXAMPLE
powershell.exe -File Invoke-AppDeployToolkit.ps1

.EXAMPLE
powershell.exe -File Invoke-AppDeployToolkit.ps1 -DeployMode Silent

.EXAMPLE
powershell.exe -File Invoke-AppDeployToolkit.ps1 -DeploymentType Uninstall

.EXAMPLE
Invoke-AppDeployToolkit.exe -DeploymentType Install -DeployMode Silent

.INPUTS
None. You cannot pipe objects to this script.

.OUTPUTS
None. This script does not generate any output.

.NOTES
Toolkit Exit Code Ranges:
- 60000 - 68999: Reserved for built-in exit codes in Invoke-AppDeployToolkit.ps1, and Invoke-AppDeployToolkit.exe
- 69000 - 69999: Recommended for user customized exit codes in Invoke-AppDeployToolkit.ps1
- 70000 - 79999: Recommended for user customized exit codes in PSAppDeployToolkit.Extensions module.

.LINK
https://psappdeploytoolkit.com

#>

[CmdletBinding()]
param
(
    # Default is 'Install'.
    [Parameter(Mandatory = $false)]
    [ValidateSet('Install', 'Uninstall', 'Repair')]
    [System.String]$DeploymentType,

    # Default is 'Auto'. Don't hard-code this unless required.
    [Parameter(Mandatory = $false)]
    [ValidateSet('Auto', 'Interactive', 'NonInteractive', 'Silent')]
    [System.String]$DeployMode,

    [Parameter(Mandatory = $false)]
    [System.Management.Automation.SwitchParameter]$SuppressRebootPassThru,

    [Parameter(Mandatory = $false)]
    [System.Management.Automation.SwitchParameter]$TerminalServerMode,

    [Parameter(Mandatory = $false)]
    [System.Management.Automation.SwitchParameter]$DisableLogging
)


##================================================
## MARK: Variables
##================================================

# Zero-Config MSI support is provided when "AppName" is null or empty.
# By setting the "AppName" property, Zero-Config MSI will be disabled.
$adtSession = @{
    # App variables.
    AppVendor = ''
    AppName = 'Notepad++'
    AppVersion = 'Latest'
    AppArch = ''
    AppLang = 'EN'
    AppRevision = '01'
    AppSuccessExitCodes = @(0)
    AppRebootExitCodes = @(1641, 3010)
    AppProcessesToClose = @('notepad++')  # Example: @('excel', @{ Name = 'winword'; Description = 'Microsoft Word' })
    AppScriptVersion = '1.0.0'
    AppScriptDate = '2026-01-15'
    AppScriptAuthor = 'ThurJ'
    RequireAdmin = $true
	# Set NoProcessDetection to $true to not set DeployMode to 'Silent' if no process found to close
	NoProcessDetection = $false

    # Install Titles (Only set here to override defaults set by the toolkit).
    InstallName = 'Notepad++ (64-bit)'
    InstallTitle = 'Notepad++ (64-bit)'

    # Script variables.
    DeployAppScriptFriendlyName = $MyInvocation.MyCommand.Name
    DeployAppScriptParameters = $PSBoundParameters
    DeployAppScriptVersion = '4.1.8'
}




##================================================
## MARK: DWT Custom Code - Start
##================================================

## Modify variables so we can use them later...
if ([System.String]::IsNullOrWhiteSpace($adtSession.InstallName)) {$adtSession.InstallName = $adtSession.AppVendor + ' ' + $adtSession.AppName}
if ([System.String]::IsNullOrWhiteSpace($adtSession.InstallTitle)) {$adtSession.InstallTitle = $adtSession.AppVendor + ' ' + $adtSession.AppName}

## remove spaces from $appName if exist
$AppNameTrimed = $($adtSession.AppName).replace(' ' , '')


## If set to true, then we will evaluate if running from UNC path, if so, copy bits locally
[System.Boolean]$netImpact = $false

# Override check open apps from setting GUI to silent
[System.Boolean]$SilentModeOverride = $false

# If set to true, the installer will use Evergreen logic to download latest bits
[System.Boolean]$Evergreen = $true

# Restart Closed Apps as USER
[System.Boolean]$RestartApps = $true



# Define an array of applications with their details
$Global:AppArray = @(
	@{
		PRODNAME 	= "$($adtSession.AppName)"
		VERSION 	= "$($adtSession.AppVersion)"
		INSTALLER	= "Evergreen"	## If this is an Evergreen package, then enter "Evergreen"
		SWITCHES 	= "/S"
		TRANS_FORM	= ""
	},
	@{
		PRODNAME 	= ""
		VERSION 	= ""
		INSTALLER	= ""
		SWITCHES 	= ""
		TRANS_FORM	= ""
	},
	@{
		PRODNAME 	= ""
		VERSION 	= ""
		INSTALLER	= ""
		SWITCHES 	= ""
		TRANS_FORM	= ""
	},
	@{
		PRODNAME 	= ""
		VERSION 	= ""
		INSTALLER	= ""
		SWITCHES 	= ""
		TRANS_FORM	= ""
	},
	@{
		PRODNAME 	= ""
		VERSION 	= ""
		INSTALLER	= ""
		SWITCHES 	= ""
		TRANS_FORM	= ""
	},
	@{
		PRODNAME 	= ""
		VERSION 	= ""
		INSTALLER	= ""
		SWITCHES 	= ""
		TRANS_FORM	= ""
	}
)

## look for INSTALLER values that equal "Evergreen" in $AppArray, and set boolean to TRUE if found
ForEach($value in $AppArray) 
{
	If ($value.INSTALLER -eq "Evergreen") 
	{
		[System.Boolean]$Evergreen = $true
	}
}





## List of Apps to restart as user
$Global:RestartAppsAsUser = @(
	@{
		FullPath 		= ''   ## Example: C:\Program Files (x86)\Cisco\Cisco Secure Client\UI\csc_ui.exe
	},
	@{
		FullPath 		= ''
	},
	@{
		FullPath 		= ''
	}
)
## Weed out empties or $null values
$RestartAppsAsUser = $RestartAppsAsUser.FullPath -ne "" -ne $null



## Add FakeApp if no app specified (this will keep AllowDeferCloseProcesses switch from throwing an error)
if ($adtSession.AppProcessesToClose.Count -lt 1)
{
	$adtSession.AppProcessesToClose = @('fakeapp')
}


##================================================
## MARK: DWT Custom Code - End
##================================================







## *********************************************************************************************************************************************
## *********************************************************************************************************************************************
## MARK: INSTALL
## *********************************************************************************************************************************************
## *********************************************************************************************************************************************

function Install-ADTDeployment
{
    [CmdletBinding()]
    param
    (
    )

    ##================================================
    ## MARK: Pre-Install
    ##================================================
    $adtSession.InstallPhase = "Pre-Install"

    ## Show Welcome Message, close processes if specified, allow up to 3 deferrals, verify there is enough disk space to complete the install, and persist the prompt.
    $saiwParams = @{
		## Will allow defer if CloseProcesses is null.  If CloseProcesses is specified but not found, will switch to silent mode (due to default of DeployMode=Auto).
        # AllowDefer = $true
		
		## Requires a CloseProcesses to be specified.  If CloseProcesses is not found, will switch to silent mode (due to default of DeployMode=Auto -- For 4.0.x behavior change DeployMode=Interactive).
		AllowDeferCloseProcesses = $true
		
        DeferDays = 7
		
        # CheckDiskSpace = $true
		
        PersistPrompt = $true
		
		## If Silent is used, then no other params other than CloseProcesses can be used!
		## The Silent switch will silently force close processes in $adtSession.AppProcessesToClose
		# Silent = $true
    }
    if ($adtSession.AppProcessesToClose.Count -gt 0)
    {
        $saiwParams.Add('CloseProcesses', $adtSession.AppProcessesToClose)
    }
    Show-ADTInstallationWelcome @saiwParams

    ## Show Progress Message (with the default message).
    Show-ADTInstallationProgress




    ## <Perform Pre-Installation tasks here>
	

	
	
	
	##================================================
	## MARK: DWT Custom Code - Start
	##================================================
	
	## Record previous version of app if found
	ForEach ($Program in $AppArray) {
		
		If ($Program.PRODNAME -ne '') {
		
			[String]$PRODNAME 	= $Program.PRODNAME
			[String]$PRODNAME 	= $PRODNAME.Trim()
			
			## Store the InstalledApp properties in object variable
			$AppInstallPresence = Get-ADTApplication -Name $PRODNAME -ErrorAction Ignore
			
			Write-ADTLogEntry -Message "Previous Versions for Upgrading [$($AppInstallPresence)]"
		}
	}
	
	
	#####################
	##    EVERGREEN    ##
	#####################
	if ($Evergreen)
	{
			Write-ADTLogEntry -Message "Evergreen flag is set to: [True]"
			Write-ADTLogEntry -Message "Will try to download latest bits from vendor website..."
		
		$SilentMode = $False
	
		# Application-specific variables
		$EvergreenAppName = "$($adtSession.AppName)"
		
		if ($isUncPath)
		{
			$EvergreenTempPath = "C:\Windows\ccmcache\Evergreen\$EvergreenAppName"
		}
		Else
		{
			$EvergreenTempPath = "$($adtSession.DirFiles)\Evergreen\$EvergreenAppName"
		}
		
		Write-ADTLogEntry -Message "EvergreenTempPath [$EvergreenTempPath]"
		
		## make sure Evergreen Temp Path is clean
		Remove-ADTFolder -Path "$EvergreenTempPath"
		
		## Create destination directory if not already there.
		New-ADTFolder -Path "$EvergreenTempPath"
		
		# Set TLS support for Powershell and parse the JSON request
		[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
			
		if ($Host.Version.Major -ge 5)
		{
			# Progress bar can significantly impact cmdlet performance
			# https://github.com/PowerShell/PowerShell/issues/2138
			$Script:ProgressPreference = "SilentlyContinue"
		}
		
		## Disable need to run Internet Explorer's first launch condition
		## This is needed due to - Invoke-WebRequest command has a dependency on the Internet Explorer assemblies and are invoking it to parse the result as per default behavior
		Set-ADTRegistryKey -Key "HKLM\SOFTWARE\Microsoft\Internet Explorer\Main" -Name "DisableFirstRunCustomize" -Type 'DWord' -Value '2'
		Set-ADTRegistryKey -Key "HKLM\SOFTWARE\Policies\Microsoft\Internet Explorer\Main" -Name "DisableFirstRunCustomize" -Type 'DWord' -Value '2'
		
		## Set default for Invoke-WebRequest to: UseBasicParsing
		$PSDefaultParameterValues=@{"Invoke-WebRequest:UseBasicParsing"=$true}
		
		
		
		
		# Download the latest stable version of the application
		
		## Show Progress Message
		If (-not($SilentMode))
		{
			Show-ADTInstallationProgress -StatusMessage "Downloading the latest $EvergreenAppName installer..." `
		}
		
		# measuring execution time is really hip these days.
		$stop_watch = [Diagnostics.Stopwatch]::StartNew()
		

		## Direct Download link
		$DownloadURI = 'https://api.github.com/repos/notepad-plus-plus/notepad-plus-plus/releases/latest'
		
		Write-ADTLogEntry -Message "Download URI [$DownloadURI]"
		
		
		$EvergreenApp = Invoke-WebRequest -Uri $DownloadURI -UseBasicParsing | ConvertFrom-Json
		
		## Filter for
		$EvergreenAppPackage = "x64.exe"
		
		
		## Get the file name
		$outFileName = $EvergreenApp.assets | where { $_.name.Contains($EvergreenAppPackage) -and !$_.name.Contains(".sig")} | Select -ExpandProperty name
		
		Write-ADTLogEntry -Message "Out File Name [$outFileName]"
		
		## $outFileName = $EvergreenApp.Headers.'Content-Disposition'.Split('=',2)[-1]
		
		## Build the download URL
		## Get the download URL from the JSON object
		$DirectDownload = $EvergreenApp.assets | where { $_.name.Contains($EvergreenAppPackage) -and !$_.name.Contains(".sig")} | Select -ExpandProperty browser_download_url
			
		
		Write-ADTLogEntry -Message "Direct Download [$DirectDownload]"
		
		## build the installer path
		$installerPath = Join-Path $EvergreenTempPath $outFileName
		
		Write-ADTLogEntry -Message "Installer Path [$installerPath]"
		
		## Save the file to the installerpath
		Invoke-WebRequest -Uri $directDownload -OutFile $installerPath -UseBasicParsing
		
		# Stop measuring execution time
		$stop_watch.Stop()
		
		$StopWatch = $stop_watch.Elapsed
		$elapsedTime = "{0:00}:{1:00}:{2:00}" -f $StopWatch.Hours, $StopWatch.Minutes, $StopWatch.Seconds
		$elapsedTime2 = "$($StopWatch.Hours) hours, $($StopWatch.Minutes) minutes, and $($StopWatch.Seconds) seconds"
		
		Write-ADTLogEntry -Message  "Total Download Time [$($elapsedTime)] -- $($elapsedTime2)"
		
		
		
		## Add the Evergreen installer to the AppArray
		Write-ADTLogEntry -Message "Updating the AppArray with the Evergreen downloaded installer..."
		ForEach($value in $AppArray) 
		{
			If ($value.INSTALLER -eq "Evergreen") 
			{
				$value.INSTALLER = $outFileName
			}
		}

		
	
	
		## Close the Download Progress dialog
		Close-ADTInstallationProgress
		
		
		
	} #End Evergreen
	
	
	
	##================================================
	## MARK: DWT Custom Code - End
	##================================================
	
	


    ##================================================
    ## MARK: Install
    ##================================================
    $adtSession.InstallPhase = "Install"

    ## Handle Zero-Config MSI installations.
    if ($adtSession.UseDefaultMsi)
    {
        $ExecuteDefaultMSISplat = @{ Action = $adtSession.DeploymentType; FilePath = $adtSession.DefaultMsiFile }
        if ($adtSession.DefaultMstFile)
        {
            $ExecuteDefaultMSISplat.Add('Transforms', $adtSession.DefaultMstFile)
        }
        Start-ADTMsiProcess @ExecuteDefaultMSISplat
        if ($adtSession.DefaultMspFiles)
        {
            $adtSession.DefaultMspFiles | Start-ADTMsiProcess -Action Patch
        }
    }





    ## <Perform Installation tasks here>
	
	
	##================================================
	## MARK: DWT Custom Code - Start
	##================================================
	
	# Install each program from the array
	ForEach ($Program in $AppArray) 
	{

		[String]$PRODNAME 	= $Program.PRODNAME
		[String]$VERSION 	= $Program.VERSION
		[String]$INSTALLER 	= $Program.INSTALLER
		[String]$SWITCHES 	= $Program.SWITCHES
		[String]$TRANS_FORM	= $Program.TRANS_FORM

		If ($PRODNAME) {$PRODNAME = $PRODNAME.trim()}
		If ($VERSION) {$VERSION = $VERSION.trim()}
		If ($INSTALLER) {$INSTALLER = $INSTALLER.trim()}
		If ($SWITCHES) {$SWITCHES = $SWITCHES.trim()}
		If ($TRANS_FORM) {$TRANS_FORM = $TRANS_FORM.trim()}

		if ([string]::IsNullOrWhiteSpace($SWITCHES)) {$SWITCHES = $Null}
		if ([string]::IsNullOrWhiteSpace($TRANS_FORM)) {$TRANS_FORM = $Null}




		If ($INSTALLER) 
		{

			Write-ADTLogEntry -Message "*** Installer: [$($INSTALLER)]"

			
			if ($Evergreen)
			{
				## Get full path of the $INSTALLER VARIABLE
				$AppInstallerPath = Get-ChildItem -Path "$EvergreenTempPath" -Include "$($INSTALLER)" -File -Recurse -ErrorAction SilentlyContinue | Select-Object FullName -ExpandProperty FullName
				
			}
			Else
			{
				## Get full path of the $INSTALLER VARIABLE
				$AppInstallerPath = Get-ChildItem -Path "$($adtSession.DirFiles)" -Include "$($INSTALLER)" -File -Recurse -ErrorAction SilentlyContinue | Select-Object FullName -ExpandProperty FullName
			}
			
			Write-ADTLogEntry -Message "*** App Installer Path: [$($AppInstallerPath)]"
			
			
			# Get extension of file
			$packageFileType = (($INSTALLER).Split('.')[-1])
			$FileInfo = $Null

			
			If ($packageFileType -eq "msi")
			{
				## Get FileInfo
				$FileInfo = Get-ADTMsiTableProperty  -Path "$appInstallerPath"
				
				If ($TRANS_FORM)
				{
					## Get full path of the $TRANS_FORM VARIABLE
					$AppTransformPath = Get-ChildItem -Path "$($adtSession.DirFiles)" -Include "$TRANS_FORM" -File -Recurse -ErrorAction SilentlyContinue | Select-Object FullName -ExpandProperty FullName
				}
			}
			
			
			If ($packageFileType -eq "exe")
			{
				## Get FileInfo
				$FileInfo = Get-ExeFileInfo -FilePath "$appInstallerPath"
	
			}
			
			

			Write-ADTLogEntry -Message "*** Switches: [$($SWITCHES)]"
			Write-ADTLogEntry -Message "*** TRANS_FORM: [$($TRANS_FORM)]"


			# Set ActionCmdlet depending on filetype
			Switch -exact ($packageFileType)
			{
				'msi'
					{ 	# Script block to install software
						If ($SWITCHES)
						{
							[scriptblock]$InstallScriptBlock =
							{
								param($PRODNAME, $VERSION, $INSTALLER, $SWITCHES, $TRANS_FORM)
								Start-ADTMsiProcess -Action 'Install' -FilePath $appInstallerPath -AdditionalArgumentList $SWITCHES -PassThru
							}
						}
						ElseIf ($TRANS_FORM)
						{
							[scriptblock]$InstallScriptBlock =
							{
								param($PRODNAME, $VERSION, $INSTALLER, $SWITCHES, $TRANS_FORM)
								Start-ADTMsiProcess -Action 'Install' -FilePath $appInstallerPath -Transforms $AppTransformPath -PassThru
							}
						}
						ElseIf (($TRANS_FORM) -and ($SWITCHES))
						{
							[scriptblock]$InstallScriptBlock =
							{
								param($PRODNAME, $VERSION, $INSTALLER, $SWITCHES, $TRANS_FORM)
								Start-ADTMsiProcess -Action 'Install' -FilePath $appInstallerPath -AdditionalArgumentList $SWITCHES -Transforms $AppTransformPath -PassThru
							}
						}
						Else
						{
							[scriptblock]$InstallScriptBlock =
							{
								param($PRODNAME, $VERSION, $INSTALLER, $SWITCHES, $TRANS_FORM)
								Start-ADTMsiProcess -Action 'Install' -FilePath $appInstallerPath -PassThru
							}
						}
					}
				'msix'
					{ 	# Script block to install software
						If ($SWITCHES)
						{
							[scriptblock]$InstallScriptBlock =
							{
								param($PRODNAME, $VERSION, $INSTALLER, $SWITCHES, $TRANS_FORM)
								Dism /Online /Add-ProvisionedAppxPackage /PackagePath:$appInstallerPath $SWITCHES
							}
						}
						Else
						{
							[scriptblock]$InstallScriptBlock =
							{
								param($PRODNAME, $VERSION, $INSTALLER, $SWITCHES, $TRANS_FORM)
								Dism /Online /Add-ProvisionedAppxPackage /PackagePath:$appInstallerPath
							}
						}
					}
				'msixbundle'
					{ 	# Script block to install software
						[scriptblock]$InstallScriptBlock = {
							param($PRODNAME, $VERSION, $INSTALLER, $SWITCHES, $TRANS_FORM)
							
							## Repairing WinGet (making sure it's preprovisioned properly)
							Repair-ADTWinGetPackageManager -Verbose
							
							Install-ADTWinGetPackage -Id "$INSTALLER" -Verbose
							
						}
					}
				'appx'
					{ 	# Script block to install software
						[scriptblock]$InstallScriptBlock = {
							param($PRODNAME, $VERSION, $INSTALLER, $SWITCHES, $TRANS_FORM)
							
							## Repairing WinGet (making sure it's preprovisioned properly)
							Repair-ADTWinGetPackageManager -Verbose
							
							Install-ADTWinGetPackage -Id "$INSTALLER" -Verbose
						}
					}
				'appxbundle'
					{ 	# Script block to install software
						[scriptblock]$InstallScriptBlock = {
							param($PRODNAME, $VERSION, $INSTALLER, $SWITCHES, $TRANS_FORM)
							
							
							## Repairing WinGet (making sure it's preprovisioned properly)
							Repair-ADTWinGetPackageManager -Verbose
							
							Install-ADTWinGetPackage -Id "$INSTALLER" -Verbose
						}
					}
				'appinstaller'
					{ 	# Script block to install software
						[scriptblock]$InstallScriptBlock = {
							param($PRODNAME, $VERSION, $INSTALLER, $SWITCHES, $TRANS_FORM)
							Add-AppxPackage -AppInstallerFile "$appInstallerPath"
						}
					}
				'exe'
					{ 	# Script block to install software
						If ($SWITCHES)
						{
							[scriptblock]$InstallScriptBlock =
							{
								param($PRODNAME, $VERSION, $INSTALLER, $SWITCHES, $TRANS_FORM)
								Start-ADTProcess -FilePath $appInstallerPath -ArgumentList $SWITCHES -PassThru
							}
						}
						Else
						{
							[scriptblock]$InstallScriptBlock =
							{
								param($PRODNAME, $VERSION, $INSTALLER, $SWITCHES, $TRANS_FORM)
								Start-ADTProcess -FilePath $appInstallerPath -PassThru
							}
						}
					}
				default {
					Write-ADTLogEntry -Message 'The installer package type was unknown. (Not an .msi, .msix(bundle), .appx(bundle) or .exe)'
					##Show-InstallationPrompt -Message 'Invalid installer package filetype specified.' -Icon Error -Timeout 60 -ButtonRight 'OK'
					##Exit-Script -ExitCode -1
				}
			} #End Switch

			# Check to see if we can grab properties from installer
			If ($FileInfo) 
			{

				[String]$appDisplayName		= $FileInfo.ProductName			# Added [0] to only retrieve first found
				[String]$appDisplayVersion	= $FileInfo.ProductVersion		# Added [0] to only retrieve first found

				## Trim leading and trailing spaces
				[String]$appDisplayName		= $appDisplayName.Trim()
				[String]$appDisplayVersion	= $appDisplayVersion.Trim()

				$StatusMessage = "Installing `"$appDisplayName`"  `($appDisplayVersion`).`r`n`r`nThank you for your patience."
			} else 
			{
				$StatusMessage = "Installing `"$($adtSession.InstallTitle)`"  `($($adtSession.AppVersion)`).`r`n`r`nThank you for your patience."
			}
			
			## Show custom InstallationProgress
	
			Show-ADTInstallationProgress -StatusMessage $StatusMessage
	

			
					
			$InstallScriptBlockLog = $InstallScriptBlock

			Write-ADTLogEntry -Message "*** ScriptBlock: [$InstallScriptBlockLog]"



			$Return = Invoke-Command -ScriptBlock $InstallScriptBlock -ArgumentList $PRODNAME, $VERSION, $INSTALLER, $SWITCHES, $TRANS_FORM
			$ReturnExitCode = $($return).Exitcode

			Write-ADTLogEntry -Message "Return Code from Invoke-Command: [$ReturnExitCode]"

			if ($ReturnExitCode -eq "3010")
			{
				$ShowReboot = $True
			}
			
			if ($Evergreen)
			{
				
				Write-ADTLogEntry "Execute Exit Code [$ReturnExitCode]"
				Write-ADTLogEntry "App Success Exit Codes [$($adtSession.AppSuccessExitCodes)]"
				
				## Check to see if 'ExitCode' is in Array of 'SuccessExitCodes'
				if ( $($adtSession.AppSuccessExitCodes) -contains $ReturnExitCode )
				{
					Write-ADTLogEntry "Execute Result Code matches App Success Exit Code"
					Write-ADTLogEntry "Purging EvergreenTempPath..."
					## Delete EvergreenTempPath
					$EvergreenTempParent = Split-Path -Path $EvergreenTempPath -Parent
					Remove-Item "$EvergreenTempParent" -Force -Recurse -ErrorAction SilentlyContinue
				}
				Else
				{
					Write-ADTLogEntry "Execute Result Code does not match App Success Exit Code"
					Write-ADTLogEntry "Will not purge EvergreenTempPath for troubleshooting"
				}
				
			} #End If Evergreen


			## Check if app installed, then stamp registry
			$appInstalled = Get-ADTApplication -Name $PRODNAME -ErrorAction Ignore
			If ($appInstalled) 
			{
				[String]$appDisplayName 	= $appInstalled[0].DisplayName		# Added [0] to only retrieve first found
				[String]$appDisplayVersion 	= $appInstalled[0].DisplayVersion	# Added [0] to only retrieve first found

				## Trim leading and trailing spaces
				[String]$appDisplayName		= $appDisplayName.Trim()
				[String]$appDisplayVersion	= $appDisplayVersion.Trim()

				## Stamp registry
				Write-ADTLogEntry -Message "Stamping registry [HKEY_LOCAL_MACHINE\SOFTWARE\DWT\Applications] with Name [$appDisplayName] and Value [$appDisplayVersion]"
				Set-ADTRegistryKey -Key 'HKEY_LOCAL_MACHINE\SOFTWARE\DWT\Applications' -Name $appDisplayName -Type 'String' -Value $appDisplayVersion
				
				
				## Get UninstallSubkey and set NoModify and NoRepair to allow
				$appUninstallSubKey = ($appInstalled).UninstallSubkey
				$appUninstallKey = ($appInstalled).UninstallKey
				
				## Set NoModify and NoRepair
				if ($appUninstallKey)
				{
					Write-ADTLogEntry -Message "Creating registry entries for NoRepair and NoModify in [$($appUninstallKey)] with a Value of [0]"
					Set-ADTRegistryKey -Key "$appUninstallKey" -Name "NoModify" -Type 'DWord' -Value 0
					Set-ADTRegistryKey -Key "$appUninstallKey" -Name "NoRepair" -Type 'DWord' -Value 0
				}
			}

			## Close the Installation Progress dialog
			Close-ADTInstallationProgress

		} # End If
	} #End For Each
	
	
	##================================================
	## MARK: DWT Custom Code - End
	##================================================
	
	
	
	


    ##================================================
    ## MARK: Post-Install
    ##================================================
    $adtSession.InstallPhase = "Post-Install"

    ## <Perform Post-Installation tasks here>
	
	
	
	
	
	##================================================
	## MARK: DWT Custom Code - Start
	##================================================
	
	## Show Progress Message
	Show-ADTInstallationProgress -StatusMessage "Configuring settings for $appDisplayName.`r`n`r`nThank you for your patience."
	
	
	
	
	## MACHINE CODE HERE ##
	
	Write-ADTLogEntry -Message "Setting up custom settings..."
	
	## Sync themes
	ROBOCOPY "$($adtSession.DirFiles)\themes" "C:\Program Files\Notepad++\themes" /MIR /XX /IS /IT /IM /R:5 /W:2 | Out-String | Write-ADTLogEntry
	
	## Sync autoCompletion
	ROBOCOPY "$($adtSession.DirFiles)\autoCompletion" "C:\Program Files\Notepad++\autoCompletion" /MIR /XX /IS /IT /IM /R:5 /W:2 | Out-String | Write-ADTLogEntry
	
	## Sync config
	Copy-ADTFileToUserProfiles -Path "$($adtSession.DirFiles)\config\config.xml" -Destination 'AppData\Roaming\Notepad++'
	## ROBOCOPY "$($adtSession.DirFiles)\config" "$env:APPDATA\Notepad++" /MIR /XX /IS /IT /IM /R:5 /W:2 | Out-String | Write-ADTLogEntry

	## Set permissions on Notepad++ folder
		## Get the ACL for an existing folder
		$existingAcl = Get-Acl -Path "C:\Program Files\Notepad++"
		
		## Set the permissions that you want to apply to the folder, in this order - User, Rights, InheritanceFlags, PropagationFlag, Action:Allow/Deny
		$permissions = $env:USERNAME, 'Read,Modify,FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow'
		
		## Create a new FileSystemAccessRule object
		$rule = New-Object -TypeName System.Security.AccessControl.FileSystemAccessRule -ArgumentList $permissions
		
		## Modify the existing ACL to include the new rule
		$existingAcl.SetAccessRule($rule)
		
		## Apply the modified access rule to the folder
		$existingAcl | Set-Acl -Path "C:\Program Files\Notepad++"
		Write-ADTLogEntry -Message "Setting ACL for [C:\Program Files\Notepad++]"
		

	## Install RobotoMono Fonts
	Install-Fonts -FontFolder "RobotoMonoFonts"
	
	
	
	

	
	
	
	

	## USER CODE HERE ##
	
	
	
	
	
	
	## Close the Installation Progress dialog
	Close-ADTInstallationProgress
	
	
	
	## Restart any apps that were closed during install
	Unblock-ADTAppExecution
	
	## Litera Compare is famous for killing Explorer during install
	Write-ADTLogEntry -Message "Checking to see if the installer killed Explorer.exe and we need to restart it..."
	if (Get-Process -Name explorer -ErrorAction SilentlyContinue) {
		Write-ADTLogEntry -Message "Explorer is running."
	} else {
		Write-ADTLogEntry -Message "Explorer is not running, attempting to start it."
		
		$runningProcessToRestart = "C:\Windows\explorer.exe"
		
		
		If ($usersLoggedOn)
		{
			Start-ADTProcessAsUser -FilePath $runningProcessToRestart -NoWait -Verbose
		}
		
		## Start-ADTProcessAsUser -FilePath "cmd.exe" -ArgumentList "/C `"explorer.exe`"" -HideWindow -NoWait
		
		## Custom DWT Function
		## Start-DWTProcessAsUser -FilePath "`"$runningProcessToRestart`""
	}
	



	if ( ($adtSession.AppProcessesToClose.Count -gt 0) )
    {
	
		ForEach ($runningProcessToRestart in $RunningProcessesToRestartFileName) {
			
			If ($usersLoggedOn)
			{
				If (Test-Path -Path $runningProcessToRestart)
				{
					Write-ADTLogEntry -Message "Attempting to restart [$runningProcessToRestart]"
					Start-ADTProcessAsUser -FilePath $runningProcessToRestart -NoWait -Verbose -ErrorAction Ignore
				}
				Else
				{
					Write-ADTLogEntry -Message "Invalid Path [$runningProcessToRestart], will not attempt to restart [$runningProcessToRestart]"
				}
			}
		
			## Workaround for above, until fixed in PSADT 4.1
			## Start-ADTProcessAsUser -FilePath "cmd.exe" -ArgumentList "/C `"$runningProcessToRestart`"" -HideWindow -NoWait
			
			## Custom DWT Function
			## Start-DWTProcessAsUser -FilePath "$runningProcessToRestart"
		}
		
    }
	



	# PAUSE

	

	if ( ($Global:RestartAppsAsUser.Count -gt 0) )
	{
	
		## Restart Additional Apps specified in $RestartAppsAsUser
		ForEach ($runningProcessToRestart in $RestartAppsAsUser) 
		{
			## Only restart the app if it was not in the list and flagged in RunningProcessesToRestartFileName
			if (-not($RunningProcessesToRestartFileName -Contains $runningProcessToRestart))
			{
		
				If ($usersLoggedOn)
				{
					If (Test-Path -Path $runningProcessToRestart)
					{
						Write-ADTLogEntry -Message "Attempting to restart [$runningProcessToRestart]"
						Start-ADTProcessAsUser -FilePath $runningProcessToRestart -NoWait -Verbose -ErrorAction Ignore
					}
				}
				Else
				{
					Write-ADTLogEntry -Message "Invalid Path [$runningProcessToRestart], will not attempt to restart [$runningProcessToRestart]"
				}
		
				<#
				$TaskName = [guid]::NewGuid().ToString()
				
				## Set new priority
				$NewPriority = 0
				
				schtasks.exe /Create /SC ONCE /ST 00:00 /RL HIGHEST /RU "INTERACTIVE" /TN "$TaskName" /TR "Powershell -NoProfile -WindowStyle Hidden -Command 'start-process '''$runningProcessToRestart''''" /F
				
				Write-ADTLogEntry -Message "Task Created [$TaskName]"
				
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
				Set-ScheduledTask -TaskName $TaskName -TaskPath $Task.TaskPath -Settings $TaskSettings
				
				$TaskNewPriority = ((Get-ScheduledTask -TaskName $TaskName).Settings).Priority
				Write-ADTLogEntry -Message "Task New Priority [$TaskNewPriority]"
				
		
				# Run the task immediately
				Write-ADTLogEntry -Message "Running Task [$TaskName]"
				schtasks /Run /TN "$TaskName"
			
				# Optional: Wait and then delete the task
				Start-Sleep -Seconds 3
				schtasks /Delete /TN "$TaskName" /f
				Write-ADTLogEntry -Message "Deleting Task [$TaskName]"
				
				#>
				
			} # End If
			Else
			{
				Write-ADTLogEntry -Message "[$runningProcessToRestart] matched [$RunningProcessesToRestartFileName], and is already flagged for restarting. Do nothing."
			}
			
		} # End ForEach
		
	} # End If
	
	
	##================================================
	## MARK: DWT Custom Code - End
	##================================================


    ## Display a message at the end of the install.
    if (!$adtSession.UseDefaultMsi)
    {
		Show-ADTInstallationPrompt -Message "$($adtSession.AppName) installation complete." -ButtonRightText 'OK' -NoWait -Timeout '5'
    }
	
	
} ## End Function - Install







## *********************************************************************************************************************************************
## *********************************************************************************************************************************************
## MARK: UNINSTALL
## *********************************************************************************************************************************************
## *********************************************************************************************************************************************


function Uninstall-ADTDeployment
{
    [CmdletBinding()]
    param
    (
    )

    ##================================================
    ## MARK: Pre-Uninstall
    ##================================================
    $adtSession.InstallPhase = "Pre-Uninstall"
	
	

	
	
	

    ## Show Welcome Message, close processes if specified, allow up to 3 deferrals, verify there is enough disk space to complete the install, and persist the prompt.
    $saiwParams = @{
		## Will allow defer if CloseProcesses is null.  If CloseProcesses is specified but not found, will switch to silent mode (due to default of DeployMode=Auto).
        # AllowDefer = $true
		
		## Requires a CloseProcesses to be specified.  If CloseProcesses is not found, will switch to silent mode (due to default of DeployMode=Auto -- For 4.0.x behavior change DeployMode=Interactive).
		AllowDeferCloseProcesses = $true
		
        DeferDays = 7
        # CheckDiskSpace = $true
        PersistPrompt = $true
    }
    if ($adtSession.AppProcessesToClose.Count -gt 0)
    {
        $saiwParams.Add('CloseProcesses', $adtSession.AppProcessesToClose)
    }
    Show-ADTInstallationWelcome @saiwParams
	
	

    ## Show Progress Message (with the default message).
    Show-ADTInstallationProgress

    ## <Perform Pre-Uninstallation tasks here>


    ##================================================
    ## MARK: Uninstall
    ##================================================
    $adtSession.InstallPhase = "Uninstall"

    ## Handle Zero-Config MSI uninstallations.
    if ($adtSession.UseDefaultMsi)
    {
        $ExecuteDefaultMSISplat = @{ Action = $adtSession.DeploymentType; FilePath = $adtSession.DefaultMsiFile }
        if ($adtSession.DefaultMstFile)
        {
            $ExecuteDefaultMSISplat.Add('Transforms', $adtSession.DefaultMstFile)
        }
        Start-ADTMsiProcess @ExecuteDefaultMSISplat
    }




    ## <Perform Uninstallation tasks here>
	
	
	
	##================================================
	## MARK: DWT Custom Code - Start
	##================================================
	
	## Remove any pre-existing installations
	## Show Progress Message
	Show-ADTInstallationProgress -StatusMessage "Checking for and uninstalling previous versions...`r`nThank you for your patience."
	
	

	
	## Remove apps in reverse install order		
	[array]::Reverse($AppArray) # <-- The magic goes here
	
	
	# UnInstall each program from the array in reverse install order
	ForEach ($Program in $AppArray) {
		
		If ($Program.PRODNAME -ne '') {
		
			[String]$PRODNAME 	= $Program.PRODNAME
			[String]$PRODNAME 	= $PRODNAME.Trim()
			
			Write-ADTLogEntry -Message "Looking for apps to uninstall matching [$PRODNAME]."
			
			## Custom uninstall for AppxPackages
			$Package = Get-AppxPackage -AllUsers | Where-Object {$_.Name -Like $PRODNAME} 
			# If package was found, proceed to remove it, otherwise add it to list of apps not found
			if ($Package) 
			{
				Write-ADTLogEntry -Message "Found AppxPackage matching [$PRODNAME] --- Removing [$Package]..."
				$Package | Remove-AppxPackage -AllUsers -ea silentlycontinue
				## Add logic to remove app from the $RunningProcessesToRestartFileName Array (so it does not try relaunching at end)
				continue # Jumps immediately to the next iteration in ForEach
			}

			
			
			
			## Store the InstalledApp properties in object variable
			$AppInstallPresence = Get-ADTApplication -Name $PRODNAME -ErrorAction Ignore
			
			Write-ADTLogEntry -Message "Matched [$($AppInstallPresence)] to [$PRODNAME]"
			#pause
			
			
			if ($AppInstallPresence) 
			{
				
				
				$AppUninstallString = $AppInstallPresence[0].UninstallString
				$AppQuietUninstallString = $AppInstallPresence[0].QuietUninstallString
				
				## not available until 4.1
				$AppUninstallStringFilePath = $AppInstallPresence[0].UninstallStringFilePath
				$AppUninstallStringArgumentList = $AppInstallPresence[0].UninstallStringArgumentList
				
				#[String]$AppUninstallString 			= $AppUninstallString.Trim()
				#[String]$AppQuietUninstallString		= $AppQuietUninstallString.Trim()
				#[String]$AppUninstallStringFilePath 	= $AppUninstallStringFilePath.Trim()
				#[String]$AppUninstallStringArgumentList	= $AppUninstallStringArgumentList.Trim()
				
				
				Write-ADTLogEntry -Message "AppUninstallString [$($AppUninstallString)]"
				Write-ADTLogEntry -Message "AppQuietUninstallString [$($AppQuietUninstallString)]"
				## not available until 4.1
				Write-ADTLogEntry -Message "AppUninstallStringFilePath [$($AppUninstallStringFilePath)]"
				Write-ADTLogEntry -Message "AppUninstallStringArgumentList [$($AppUninstallStringArgumentList)]"
				
				#PAUSE
				
				
				
				if ($AppUninstallString)
				{
				
					Write-ADTLogEntry -Message "AppUninstallString: [$AppUninstallString]"
					#pause
					
				
					[String]$AppDisplayName 	= $AppInstallPresence[0].DisplayName		# Added [0] to only retrieve first found
					[String]$AppDisplayVersion 	= $AppInstallPresence[0].DisplayVersion		# Added [0] to only retrieve first found
					
					[String]$AppDisplayName 	= $AppDisplayName.Trim()
					[String]$AppDisplayVersion	= $AppDisplayVersion.Trim()
				
				
					#$StatusMessage = "Uninstalling $AppDisplayName $AppDisplayVersion.`r`n`r`nThank you for your patience."
					
					## Close the Installation Progress dialog
					Close-ADTInstallationProgress
					
					
					
					## Show Progress Message
					Show-ADTInstallationProgress -StatusMessage "Uninstalling `"$appDisplayName`"  `($appDisplayVersion`).`r`n`r`nThank you for your patience."
					

						
						
					## Uninstall based on either AppQuietUninstallString or AppUninstallString
					
					## First check for AppQuietUninstallString, and use that option first
					if (-not([System.String]::IsNullOrWhiteSpace($AppQuietUninstallString)) )
					{
						## Parse AppQuietUninstallString and split into Program and Arguments
						$prog, $myargs = $AppQuietUninstallString | select-string '("[^"]*"|\S)+' -AllMatches | % matches | % value
						$prog = $prog -replace '"',$null

						if (-not([System.String]::IsNullOrWhiteSpace($prog)) )
						{
							[System.String]$ProgramPath = $prog.Trim()
						}
						if (-not([System.String]::IsNullOrWhiteSpace($myargs)) )
						{
							[System.String]$ArgumentList = $myargs.Trim()
						}
						
						if (-not([System.String]::IsNullOrWhiteSpace($ProgramPath)) )
						{
							$ProgramPathParent = Split-Path -Path $ProgramPath
						}
						
						Write-ADTLogEntry -message "Uninstall Command [$ProgramPath]"
						Write-ADTLogEntry -message "Parent Path [$ProgramPathParent]"
						Write-ADTLogEntry -message "Uninstall Switches [$ArgumentList]"
						
						## Copy uninstall files to ccmcache for elevation during uninstall (unins000.exe requires companion file unins000.dat so copy whole directory)
						$UninstallTempPath = "C:\Windows\ccmcache\UninstallTemp"
						Copy-ADTFile -Path "$($ProgramPathParent)\*" -Destination $UninstallTempPath
						
						
						## Get File Name
						[System.String]$ProgramFileName = Split-Path -Path $ProgramPath -Leaf
						Write-ADTLogEntry -message "Program file name [$ProgramFileName]"
						
						## Build TempFile Path
						[System.String]$ProgramTempFilePath = "$UninstallTempPath\$ProgramFileName"
						Write-ADTLogEntry -message "Program temp file path [$ProgramTempFilePath]"
						
						## Perform the uninstall from ccmcache or Program Files
						if ($ProgramPath -match "7-Zip")
						{
							Write-ADTLogEntry -message "Will use [$ProgramPathParent] to uninstall"
							## Special processing for 7-Zip (must be unistalled from Program Files, not ccmcache)
							$ExecuteResult = Start-ADTProcess -FilePath $ProgramPath -ArgumentList $ArgumentList -WindowStyle 'Hidden' -PassThru -verbose
							## May need to unregister this dll as it seems to be the explorer integration, and we cannot delete the 7-Zip folder
							regsvr32.exe /s /u "C:\Program Files\7-Zip\7-zip.dll" | Out-Null
						}
						else
						{
							Write-ADTLogEntry -message "Will use [$UninstallTempPath] to uninstall"
							## Uninstall from ccmcache to allow for elevation
							$ExecuteResult = Start-ADTProcess -FilePath $ProgramTempFilePath -ArgumentList $ArgumentList -WindowStyle 'Hidden' -PassThru -verbose
						}
						
						
						$ReturnExitCode = $($ExecuteResult).Exitcode
						
						Write-ADTLogEntry "Execute Exit Code [$($ExecuteResult.ExitCode)]"
						Write-ADTLogEntry "App Success Exit Codes [$($adtSession.AppSuccessExitCodes)]"
						
						## Check to see if 'ExitCode' is in Array of 'SuccessExitCodes'
						if ( $($adtSession.AppSuccessExitCodes) -contains $ReturnExitCode )
						{
							Write-ADTLogEntry "Execute Result Code matches App Success Exit Code"
							Write-ADTLogEntry "Purging UninstallPath..."
							
							## Remove ProgramFiles Path
							Remove-ADTFolder -Path $ProgramPathParent -ErrorAction Ignore
							## Remove Temp Path
							Remove-ADTFolder -Path $UninstallTempPath -ErrorAction Ignore
						}
						Else
						{
							Write-ADTLogEntry "Execute Result Code does not match App Success Exit Code"
							Write-ADTLogEntry "Will not purge ccmcache UninstallTempPath for troubleshooting"
						}

					}
					Else  ## No AppQuietUninstallString, so use AppUninstallString, but check if msiexec or exe
					{
						
						Write-ADTLogEntry "No QuietUninstallString found, will use UninstallString..."
						#PAUSE

						If ($AppUninstallString -notmatch 'MsiExec')
						{
							
							## Parse AppQuietUninstallString and split into Program and Arguments
							$prog, $myargs = $AppUninstallString -split '(?=/)'
							$prog = $prog -replace '"',$null
							
							if (-not([System.String]::IsNullOrWhiteSpace($prog)) )
							{
								[System.String]$ProgramPath = $prog.Trim()
							}
							if (-not([System.String]::IsNullOrWhiteSpace($myargs)) )
							{
								[System.String]$ArgumentList = $myargs.Trim()
							}
							
							if (-not([System.String]::IsNullOrWhiteSpace($ProgramPath)) )
							{
								$ProgramPathParent = Split-Path -Path $ProgramPath
							}
							
							Write-ADTLogEntry -message "Uninstall Command [$ProgramPath]"
							Write-ADTLogEntry -message "Parent Path [$ProgramPathParent]"
							Write-ADTLogEntry -message "Uninstall Switches [$ArgumentList]"
							
							## Need to add a silent switch for IPDAS PDF Writer uninstall
							if ($ProgramPath -match "unInstpw64")
							{
								$ArgumentList = "$ArgumentList /s"
							}
							
							## Need to add a silent switch for GPL Ghostscript uninstall
							if ($ProgramPath -match "uninstgs")
							{
								# Case sensitive - need uppercase 'S'
								$ArgumentList = '/S'
							}
							
							
							## See if there are args specified, and if so use Start-ADTProcess, else use Uninstall-ADTApplication
							if (-not([System.String]::IsNullOrWhiteSpace($ArgumentList)) )
							{
								Start-ADTProcess -FilePath $ProgramPath -ArgumentList $ArgumentList -WindowStyle 'Hidden' -PassThru -verbose
							}
							Else
							{
								Uninstall-ADTApplication -Name $AppDisplayName -NameMatch 'Contains' -ApplicationType 'EXE' -PassThru
							}
						}	
						

						If ($AppUninstallString -match 'MsiExec')
						{
							Write-ADTLogEntry -message "Uninstall Command: Uninstall-ADTApplication -Name `"$AppDisplayName`""
							#pause
							$return = Uninstall-ADTApplication -Name $AppDisplayName -ApplicationType 'MSI' -PassThru -ErrorAction SilentlyContinue
							$ReturnExitCode = $($return).Exitcode
							
							if ($ReturnExitCode -eq "3010")
							{
								$ShowReboot = $True
							}
						}
					} ## End Else
					
				
					# Remove application from registry
					Remove-ADTRegistryKey -Key 'HKEY_LOCAL_MACHINE\SOFTWARE\DWT\Applications' -Name $appDisplayName -ErrorAction Ignore
					
					# Remove application from registry (cleanup of perhaps older differently names of same app)
					Remove-ADTRegistryKey -Key 'HKEY_LOCAL_MACHINE\SOFTWARE\DWT\Applications' -Name $($adtSession.AppName) -ErrorAction Ignore
					
					# Remove application from registry (cleanup of perhaps older differently names of same app)
					Remove-ADTRegistryKey -Key 'HKEY_LOCAL_MACHINE\SOFTWARE\DWT\Applications' -Name $PRODNAME -ErrorAction Ignore
					
				
				} #End If $AppUninstallString
				Else
				{
					Write-ADTLogEntry -Message "No AppUninstallString found..." -Severity 2
				}
				
			} # End If AppInstallPresence
			
		} # End If $Program.PRODNAME
		
	} #End For Each
	
	## Close the Installation Progress dialog
	Close-ADTInstallationProgress
	
	## Reverse App Array, so if ReInstall is being used the install order will start top down	
	[array]::Reverse($AppArray) # <-- The magic goes here
	
	##================================================
	## MARK: DWT Custom Code - End
	##================================================
	
	
	


    ##================================================
    ## MARK: Post-Uninstallation
    ##================================================
    $adtSession.InstallPhase = "Post-Uninstall"

    ## <Perform Post-Uninstallation tasks here>
	
	
	
	
	##================================================
	## MARK: DWT Custom Code - Start
	##================================================
	
	## Restart any apps that were closed during install
	Unblock-ADTAppExecution
	
	## Litera Compare is famous for killing Explorer during install
	Write-ADTLogEntry -Message "Checking to see if the installer killed Explorer.exe and we need to restart it..."
	if (Get-Process -Name explorer -ErrorAction SilentlyContinue) {
		Write-ADTLogEntry -Message "Explorer is running."
	} else {
		Write-ADTLogEntry -Message "Explorer is not running, attempting to start it."
		
		$runningProcessToRestart = "C:\Windows\explorer.exe"
		
		
		If ($usersLoggedOn)
		{
			Start-ADTProcessAsUser -FilePath $runningProcessToRestart -NoWait -Verbose
		}
		
		## Start-ADTProcessAsUser -FilePath "cmd.exe" -ArgumentList "/C `"explorer.exe`"" -HideWindow -NoWait
		
		## Custom DWT Function
		## Start-DWTProcessAsUser -FilePath "`"$runningProcessToRestart`""
	}
	



	if ( ($adtSession.AppProcessesToClose.Count -gt 0) -and ($($adtSession.DeploymentType) -ine 'Repair') )
    {
	
		ForEach ($runningProcessToRestart in $RunningProcessesToRestartFileName) {
			
			If ($usersLoggedOn)
			{
				If (Test-Path -Path $runningProcessToRestart)
				{
					Write-ADTLogEntry -Message "Attempting to restart [$runningProcessToRestart]"
					Start-ADTProcessAsUser -FilePath $runningProcessToRestart -NoWait -Verbose -ErrorAction Ignore
				}
				Else
				{
					Write-ADTLogEntry -Message "Invalid Path [$runningProcessToRestart], will not attempt to restart [$runningProcessToRestart]"
				}
			}
		
			## Workaround for above, until fixed in PSADT 4.1
			## Start-ADTProcessAsUser -FilePath "cmd.exe" -ArgumentList "/C `"$runningProcessToRestart`"" -HideWindow -NoWait
			
			## Custom DWT Function
			## Start-DWTProcessAsUser -FilePath "$runningProcessToRestart"
		}
		
    }
	



	# PAUSE

	

	if ( ($Global:RestartAppsAsUser.Count -gt 0) -and ($($adtSession.DeploymentType) -ine 'Repair') )
	{
	
		## Restart Additional Apps specified in $RestartAppsAsUser
		ForEach ($runningProcessToRestart in $RestartAppsAsUser) 
		{
			## Only restart the app if it was not in the list and flagged in RunningProcessesToRestartFileName
			if (-not($RunningProcessesToRestartFileName -Contains $runningProcessToRestart))
			{
		
				If ($usersLoggedOn)
				{
					If (Test-Path -Path $runningProcessToRestart)
					{
						Write-ADTLogEntry -Message "Attempting to restart [$runningProcessToRestart]"
						Start-ADTProcessAsUser -FilePath $runningProcessToRestart -NoWait -Verbose -ErrorAction Ignore
					}
				}
				Else
				{
					Write-ADTLogEntry -Message "Invalid Path [$runningProcessToRestart], will not attempt to restart [$runningProcessToRestart]"
				}
		
				<#
				$TaskName = [guid]::NewGuid().ToString()
				
				## Set new priority
				$NewPriority = 0
				
				schtasks.exe /Create /SC ONCE /ST 00:00 /RL HIGHEST /RU "INTERACTIVE" /TN "$TaskName" /TR "Powershell -NoProfile -WindowStyle Hidden -Command 'start-process '''$runningProcessToRestart''''" /F
				
				Write-ADTLogEntry -Message "Task Created [$TaskName]"
				
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
				Set-ScheduledTask -TaskName $TaskName -TaskPath $Task.TaskPath -Settings $TaskSettings
				
				$TaskNewPriority = ((Get-ScheduledTask -TaskName $TaskName).Settings).Priority
				Write-ADTLogEntry -Message "Task New Priority [$TaskNewPriority]"
				
		
				# Run the task immediately
				Write-ADTLogEntry -Message "Running Task [$TaskName]"
				schtasks /Run /TN "$TaskName"
			
				# Optional: Wait and then delete the task
				Start-Sleep -Seconds 3
				schtasks /Delete /TN "$TaskName" /f
				Write-ADTLogEntry -Message "Deleting Task [$TaskName]"
				
				
				#>
				
			} # End If
			Else
			{
				Write-ADTLogEntry -Message "[$runningProcessToRestart] matched [$RunningProcessesToRestartFileName], and is already flagged for restarting. Do nothing."
			}
			
		} # End ForEach
		
	} # End If
	
	

	
	## Display a message at the end of the uninstall.
    if ( (!$adtSession.UseDefaultMsi) -and (!$adtSession.DeploymentType -eq 'Repair') )
    {
        Show-ADTInstallationPrompt -Message "$($adtSession.AppName) uninstallation complete." -ButtonRightText 'OK' -NoWait -Timeout '5'
    }
	
	
	##================================================
	## MARK: DWT Custom Code - End
	##================================================
	
	
	
	
	
} ## End Fuction - Uninstall







## *********************************************************************************************************************************************
## *********************************************************************************************************************************************
## MARK: REPAIR
## *********************************************************************************************************************************************
## *********************************************************************************************************************************************

function Repair-ADTDeployment
{
    [CmdletBinding()]
    param
    (
    )

    ##================================================
    ## MARK: Repair
    ##================================================
    $adtSession.InstallPhase = "Repair"

	## Call Uninstall and then Install
	Uninstall-ADTDeployment
	Install-ADTDeployment
	
} ## End Function - Repair








##================================================
## MARK: Initialization
##================================================

# Set strict error handling across entire operation.
$ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
$ProgressPreference = [System.Management.Automation.ActionPreference]::SilentlyContinue
Set-StrictMode -Version 1

# Import the module and instantiate a new session.
try
{
    # Import the module locally if available, otherwise try to find it from PSModulePath.
    if (Test-Path -LiteralPath "$PSScriptRoot\PSAppDeployToolkit\PSAppDeployToolkit.psd1" -PathType Leaf)
    {
        Get-ChildItem -LiteralPath "$PSScriptRoot\PSAppDeployToolkit" -Recurse -File | Unblock-File -ErrorAction Ignore
        Import-Module -FullyQualifiedName @{ ModuleName = "$PSScriptRoot\PSAppDeployToolkit\PSAppDeployToolkit.psd1"; Guid = '8c3c366b-8606-4576-9f2d-4051144f7ca2'; ModuleVersion = '4.1.8' } -Force
    }
    else
    {
        Import-Module -FullyQualifiedName @{ ModuleName = 'PSAppDeployToolkit'; Guid = '8c3c366b-8606-4576-9f2d-4051144f7ca2'; ModuleVersion = '4.1.8' } -Force
    }

    # Open a new deployment session, replacing $adtSession with a DeploymentSession.
    $iadtParams = Get-ADTBoundParametersAndDefaultValues -Invocation $MyInvocation
    $adtSession = Remove-ADTHashtableNullOrEmptyValues -Hashtable $adtSession
    $adtSession = Open-ADTSession @adtSession @iadtParams -PassThru
}
catch
{
    $Host.UI.WriteErrorLine((Out-String -InputObject $_ -Width ([System.Int32]::MaxValue)))
    exit 60008
}


##================================================
## MARK: Invocation
##================================================

# Commence the actual deployment operation.
try
{
    # Import any found extensions before proceeding with the deployment.
    Get-ChildItem -LiteralPath $PSScriptRoot -Directory | & {
        process
        {
            if ($_.Name -match 'PSAppDeployToolkit\..+$')
            {
                Get-ChildItem -LiteralPath $_.FullName -Recurse -File | Unblock-File -ErrorAction Ignore
                Import-Module -Name $_.FullName -Force
				
            }
        }
    }
	
	
	##================================================
	## MARK: DWT Custom Code - Start
	##================================================
	
	# Importing 3rd Party Modules into the Session before proceeding with the deployment.
    $ImportedModules = @()
    Get-Item -Path $PSScriptRoot\3rdParty.Modules\* | & {
        process
        {
            $ImportedModules += $_.Name
            Get-ChildItem -LiteralPath $_.FullName -Recurse -File | Unblock-File -ErrorAction Ignore
            Import-Module -Name $_.FullName -Force -ErrorAction Ignore
			Write-ADTLogEntry -Message "Importing 3rdParty Module [$_]"
        }
    }
	<#
	 # Importing Modules into the Session
    $ImportedModules = @()
    Get-Item -Path $PSScriptRoot\Modules\* | & {
        process
        {
            $ImportedModules += $_.Name
            Get-ChildItem -LiteralPath $_.FullName -Recurse -File | Unblock-File -ErrorAction Ignore
            Import-Module -Name $_.FullName -Force
        }
    }
	#>
	
	
	## RoboCopy Log
	[System.String]$RobologName = 'ROBOCOPY' + '__' + $($adtSession.AppName) + '_' + $deploymentType + '_' + $(Get-Date -Format 'MM-dd-yyyy_h.mm.ss tt') + '.log'
	[System.String]$RoboLog = "C:\DWT\Logs\Supplemental\$RobologName"
	
	## WinGet Log
	[System.String]$WinGetlogName = 'WINGET' + '__' + $($adtSession.AppName) + '_' + $deploymentType + '_' + $(Get-Date -Format 'MM-dd-yyyy_h.mm.ss tt') + '.log'
	[System.String]$WinGetLog = "C:\DWT\Logs\Supplemental\$WinGetlogName"
	
	# Create destination log directories if not already there.
	[System.IO.Directory]::CreateDirectory('C:\DWT\Logs') | Out-Null
	[System.IO.Directory]::CreateDirectory('C:\DWT\Logs\Supplemental') | Out-Null
	[System.IO.Directory]::CreateDirectory('C:\Windows\Logs\DWT') | Out-Null
	[System.IO.Directory]::CreateDirectory('C:\Windows\Logs\DWT\Supplemental') | Out-Null
	
	
	
	## Discover Working Directory and parent paths
	$workingDirectoryPath = if ($PSScriptRoot) { $PSScriptRoot } `
    elseif ($psIse) { split-path $psIse.CurrentFile.FullPath } `
    elseif ($psEditor) { split-path $psEditor.GetEditorContext().CurrentFile.Path }

    Write-ADTLogEntry -Message "Working Directory Path: $($workingDirectoryPath)" 


	$workingDirectoryParentPath = Split-Path -Path $workingDirectoryPath -Parent
	Write-ADTLogEntry -Message "Working Directory Parent Path: $($workingDirectoryParentPath)" 


	[System.boolean]$isUncPath = ([System.Uri]$workingDirectoryPath).IsUnc

	Write-ADTLogEntry -Message "Running from UNC share [$isUncPath]" 

	
	if ($netImpact)
	{
		Write-ADTLogEntry -Message "Network disruption is set to: [True]"
		[System.string]$setupTemp = "C:\Windows\ccmcache\$($AppNameTrimed)_$($adtSession.AppVersion)"
		Write-ADTLogEntry -Message "Will create temp setup directory at: $($setupTemp)"
	}
	
	## Check if running from UNC and has possible network disruption impact (like installing VPN client)
	if (($isUncPath) -and ($netImpact))
	{
		Write-ADTLogEntry -Message "Dangerous condition met: Running from UNC share while possibly on an active VPN connection!!!!"
		Write-ADTLogEntry -Message "Will attempt to Copy files locally, and then re-run the installation from 'C:\Windows\ccmcache'..."
		Write-ADTLogEntry -Message "Copying Install package locally via Robocopy..."

		ROBOCOPY "$workingDirectoryPath" "$setupTemp" /MIR /XX /IS /IT /IM /R:2 /W:2 /LOG+:$RoboLog

		Write-ADTLogEntry -Message "Ending log, and handing over install and logging to local copy of Deploy-Application.ps1..."

		Show-ADTDialogBox -Title "Potential Network Disruption" -Text "Dangerous condition met: Running from UNC share while possibly on an active VPN connection!`r`n`r`nAttempting to Copy files locally, and then re-run the installation from 'C:\Windows\ccmcache'..." -Icon 'Exclamation' -Timeout 30


		## EXIT
		Unblock-ADTAppExecution
		## Re-Kick off the local install.bat file
		## Start-Process -FilePath "$setupTemp\Install.bat"
		Start-ADTProcess -FilePath "$PSHOME\powershell.exe" -ArgumentList "-ExecutionPolicy Bypass -Command & {& Start-Sleep -seconds 5; $setupTemp\Invoke-AppDeployToolkit.ps1 -DeploymentType $DeploymentType -AllowRebootPassThru;}" -ErrorAction 'SilentlyContinue'

		## Close-ADTSession #this code to indicate that installer is kicking off from ccmcache
	}
	
	
	## Unblock any installers in the $dirFiles and $dirSupportFiles folders
	Get-ChildItem -Path "$($adtSession.DirFiles)" -Recurse | Unblock-File -ErrorAction Ignore
	Get-ChildItem -Path "$($adtSession.DirSupportFiles)" -Recurse | Unblock-File -ErrorAction Ignore

	
	
	if ($adtSession.AppProcessesToClose.Count -gt 0)
    {

		## Get all running processes to close. -- This is a custom DWT Function in "PSAppDeployToolkit.Extensions.psm1"
		$Global:RunningProcessesToRestart = Get-ADTRunningProcesses $adtSession.AppProcessesToClose
		
		## Create an array for runningProcessesToReStart (This is the full path to process)
		## Since the full path may change between versions, we will populate at runtime
		## Not using the runningProcessesToReStartArray currently
		## $Global:runningProcessesToReStartArray = @()
		
		## Process to restart Count
		$Global:runningProcessesToReStartCount = $Global:runningProcessesToReStart.Count
		Write-ADTLogEntry -Message "Running Processes to Resart Count [$Global:runningProcessesToReStartCount]"
		
		if ($Global:runningProcessesToReStart.Count -gt 0)
		{
			$Global:RunningProcessesToRestartFileName = $Global:RunningProcessesToRestart.FileName | Sort-Object -Unique
		
			## $RunningProcessesToRestartFileName = $RunningProcessesToRestart.FileName
			Write-ADTLogEntry -Message "*** App Processes to Restart [$RunningProcessesToRestartFileName]"
		}
		# pause
    
		Else
		{
			Write-ADTLogEntry -Message "*** No App Processes to Restart, will set variable to null"
			$Global:RunningProcessesToRestartFileName = $null
		}
	
	}
	
	
	
	##================================================
	## MARK: DWT Custom Code - End
	##================================================
	

    # Invoke the deployment and close out the session.
    & "$($adtSession.DeploymentType)-ADTDeployment"
    Close-ADTSession
}
catch
{
    # An unhandled error has been caught.
    $mainErrorMessage = "An unhandled error within [$($MyInvocation.MyCommand.Name)] has occurred.`n$(Resolve-ADTErrorRecord -ErrorRecord $_)"
    Write-ADTLogEntry -Message $mainErrorMessage -Severity 3

    ## Error details hidden from the user by default. Show a simple dialog with full stack trace:
    # Show-ADTDialogBox -Text $mainErrorMessage -Icon Stop -NoWait

    ## Or, a themed dialog with basic error message:
    # Show-ADTInstallationPrompt -Message "$($adtSession.DeploymentType) failed at line $($_.InvocationInfo.ScriptLineNumber), char $($_.InvocationInfo.OffsetInLine):`n$($_.InvocationInfo.Line.Trim())`n`nMessage:`n$($_.Exception.Message)" -ButtonRightText OK -Icon Error -NoWait

    Close-ADTSession -ExitCode 60001
}

