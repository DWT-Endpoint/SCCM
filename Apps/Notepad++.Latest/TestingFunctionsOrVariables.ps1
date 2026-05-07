Install-Module -Name PSAppDeployToolkit -MinimumVersion 4.1.7 -force

Import-Module -Name PSAppDeployToolkit -MinimumVersion 4.1.7 -force

Open-ADTSession -SessionState $ExecutionContext.SessionState

## Test stuff

Close-ADTSession