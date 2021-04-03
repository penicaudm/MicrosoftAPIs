[cmdletbinding ()]
param (
    [parameter (Position = 0, Mandatory)]
    [ValidateNotnullorEmpty ()]
    [string] $UserPrincipalName,

    [parameter (Position = 1)]
    [ValidateNotnullorEmpty ()]
    [string] $TenantID,

    [parameter (Position = 2, Mandatory)]
    [ValidateNotnullorEmpty ()]
    [string] $ADObjectGUID
)

function Convert-ToImmutableID {
    param (
        [parameter (Mandatory, Position = 0)]
        [string] $ObjectGUID
    )
    [System.Convert]::ToBase64String(([guid]$ObjectGUID).ToByteArray())
}

# STEP1 : get UPN and OBjectGUID on local AD, import them with CLIXml or CSV or JSON to your local powershell
# you can also run the script from your AD server or whatever.

# STEP2 : Connect MSOL online

# STEP3 : Update ImmutableID /w Set-MSOLUser
#region Modules
Write-Verbose "[+]Starting Script"

if ($null -eq (Get-Module MSOnline)) 
{
    Import-Module MSOnline 4>$null
    Write-Verbose "[+] Loaded module MSOnline"
}
else 
{
    Write-Verbose "[+] Module MSOnline already loaded"
}
#endregion Modules
#region MSOL
if ($null -eq (Get-MsolDomain)) 
{
    Connect-MsolService 
    if ($?) #yes this is a bad practice please don't attack me.
    {
        Write-Verbose "[+] Sucessfully connected to MSOnline"
    }
    else 
    {
        Write-Error "[-] Error connecting to MSOnline!"
    }
}
#endregion MSOL

Write-Verbose "[+] Processing User $UserPrincipalName"
Write-Verbose "[+] Generating Immutable ID"
try
{
    $ImmutableID = Convert-ToImmutableID -ObjectGUID $ADObjectGUID
    Set-MsolUser -UserPrincipalName $UserPrincipalName -TenantId $TenantID -ImmutableId $ImmutableID
}
catch
{
    throw $_
    Write-Error "error updating user!"
}
