#  All in one PS Script to rename Intune devices
#requires -Version 5.0
[cmdletbinding (SupportsShouldProcess)]
param (
    # Cannot be used if MFA is on the account.
    [parameter ()]
    [System.Management.Automation.PSCredential] $Credentials,

    # The CSV should contain a property called wlanmacaddress which is the MAC of wifi NIC. 
    # This was done for laptops ordered from Lenovo, other OEMs may not have the same attributes
    # Obviously, the CSV must contain a desired device name
    [parameter ()]
    [Validatescript (
        {
            Test-path $_
        }
    )]
    [string] $CSVPath,

    [parameter ()]
    [string] $CustomerTenant
)
$requiredModules = "Microsoft.graph.intune"

$RequiredModules | ForEach-Object {
    If ($null -eq (Get-Module $_ )) 
    {
        Import-Module $_ -ErrorAction Stop 4>$null
    }
}
#region Functions
function Rename-IntuneDevice
{
    [cmdletbinding (SupportsShouldProcess)]
    param(
        [Parameter (Mandatory, Position = 0)]
        [ValidateNotNullorEmpty ()]
        [string] $ManagedDeviceID,

        [parameter (Mandatory, Position = 1)]
        [ValidateNotNullorEmpty ()]
        [string] $NewDeviceName,

        [parameter (Mandatory,Position = 2)]
        [ValidateNotNullorEmpty ()]
        [string] $OldDeviceName
    )
    if ($OldDeviceName -ne $NewDeviceName)
    {

        ## Data ##

        $DeviceID = $ManagedDeviceID
        $Resource = "deviceManagement/managedDevices('$DeviceID')/setDeviceName"
        $GraphApiVersion = "Beta"
        $URI = "https://graph.microsoft.com/$graphApiVersion/$($resource)"
        
        $JSONPayload = @"
{
deviceName:"$NewDeviceName"
}
"@


        ## 
        # Implement -whatif
        if ($PSCmdlet.ShouldProcess($OldDeviceName,"Set name $NewDeviceName"))
        {
            Write-Verbose "Renaming device $OldDeviceName to $NewDeviceName"
            Invoke-MSGraphRequest -HttpMethod POST -Url $uri -Content $JSONPayload -Verbose -ErrorAction Continue
        }
    }
    else 
    {
        Write-Verbose "Not renaming device $OldDeviceName because it already has the correct name"
    }
}
#endregion Functions
#region GraphAuth
try
{
    # Set auth URI 
    Update-MSGraphEnvironment -AuthUrl "https://login.microsoftonline.com/$CustomerTenant" -SchemaVersion 'beta' -Verbose 

    # Connect to Graph
    Connect-MSGraph -Credential $Credentials -Verbose 
}
catch
{
    throw "Error connecting to Graph!"
}
#endregion GraphAuth

# Get a list of devices managed by intune
$IntuneDevices = Get-IntuneManagedDevice
if ($IntuneDevices.Count -gt 0)
{
    Write-Verbose "Found $($IntuneDevices.Count) devices."
}
else
{
    Write-Error "Could not retrieve devices from Graph API"
    exit(1)
}

# Get a the data needed to create a key-value pair to perform operations
$CSVData = Import-Csv $CSVPath -ErrorAction Stop 4>$null | Where-Object { -not [string]::IsNullOrEmpty($_.Serial) }

# Build a matching data table 

$CommonMacAddresses = Compare-Object -IncludeEqual `
    -ReferenceObject ( $IntuneDevices.WifiMacAddress | Where-Object { -not [string]::IsNullOrEmpty($_) } ) `
    -DifferenceObject ( $CSVData | Select-Object -ExpandProperty WlanMac) `
    | Where-Object Sideindicator -eq "==" | Select-Object -ExpandProperty Inputobject

# Get the objects that match to build parameter values to rename the devices
foreach ($MAC in $CommonMacAddresses)
{
    $NewDeviceName = ( $CSVData.Where( { ($_.WlanMac) -eq $MAC }) | Select-Object -ExpandProperty Name )
    $DeviceObject = $IntuneDevices.Where( { $_.Wifimacaddress -eq $MAC  } ) | Select-Object DeviceName,managedDeviceId

    $OldName = $DeviceObject.DeviceName # used for whatif and not repeat unecessary operations
    $ManagedDeviceID = $DeviceObject.managedDeviceId
    # if values are not null, rename the device

    if (-not ($null -eq $ManagedDeviceID) -or ($null -eq $NewDeviceName))
    {   
        # perform operations on graph API.
        Rename-IntuneDevice -ManagedDeviceID $ManagedDeviceID -NewDeviceName $NewDeviceName -OldDeviceName $OldName
    }
}
# Exemple object retrieved from graph API
# redacted properties are in the {type} format.
<#
TypeName: microsoft.graph.managedDevice

Name                                      MemberType   Definition                                                                                                                         
----                                      ----------   ----------                                                                                                                         
activationLockBypassCode                  NoteProperty object activationLockBypassCode=null                                                                                               
androidSecurityPatchLevel                 NoteProperty string androidSecurityPatchLevel=                                                                                                  
azureADDeviceId                           NoteProperty string azureADDeviceId={guid}                                                                        
azureADRegistered                         NoteProperty bool azureADRegistered=True                                                                                                        
complianceGracePeriodExpirationDateTime   NoteProperty datetime complianceGracePeriodExpirationDateTime=31/12/9999 23:59:59                                                               
complianceState                           NoteProperty string complianceState=compliant                                                                                                   
configurationManagerClientEnabledFeatures NoteProperty object configurationManagerClientEnabledFeatures=null                                                                              
deviceActionResults                       NoteProperty Object[] deviceActionResults=System.Object[]                                                                                       
deviceCategoryDisplayName                 NoteProperty string deviceCategoryDisplayName=Unknown                                                                                           
deviceEnrollmentType                      NoteProperty string deviceEnrollmentType=windowsAzureADJoin                                                                                     
deviceHealthAttestationState              NoteProperty object deviceHealthAttestationState=null                                                                                           
deviceName                                NoteProperty string deviceName={string}                                                                                                  
deviceRegistrationState                   NoteProperty string deviceRegistrationState=registered                                                                                          
easActivated                              NoteProperty bool easActivated=False                                                                                                            
easActivationDateTime                     NoteProperty datetime easActivationDateTime=01/01/0001 00:00:00                                                                                 
easDeviceId                               NoteProperty string easDeviceId=                                                                                                                
emailAddress                              NoteProperty string emailAddress={string}                                                                                        
enrolledDateTime                          NoteProperty datetime enrolledDateTime={date}                                                                                     
exchangeAccessState                       NoteProperty string exchangeAccessState=none                                                                                                    
exchangeAccessStateReason                 NoteProperty string exchangeAccessStateReason=none                                                                                              
exchangeLastSuccessfulSyncDateTime        NoteProperty datetime exchangeLastSuccessfulSyncDateTime=01/01/0001 00:00:00                                                                    
freeStorageSpaceInBytes                   NoteProperty long freeStorageSpaceInBytes=116071071744                                                                                          
id                                        NoteProperty string id={guid}                                                                                     
imei                                      NoteProperty string imei=                                                                                                                       
isEncrypted                               NoteProperty bool isEncrypted=False                                                                                                             
isSupervised                              NoteProperty bool isSupervised=False                                                                                                            
jailBroken                                NoteProperty string jailBroken=Unknown                                                                                                          
lastSyncDateTime                          NoteProperty datetime lastSyncDateTime={date}                                                                                  
managedDeviceName                         NoteProperty string managedDeviceName={string}                                                                        
managedDeviceODataType                    NoteProperty string managedDeviceODataType=microsoft.graph.managedDevice                                                                        
managedDeviceOwnerType                    NoteProperty string managedDeviceOwnerType=company                                                                                              
managedDeviceReferenceUrl                 NoteProperty string managedDeviceReferenceUrl=https://graph.microsoft.com/{graph API version}/deviceManagement/managedDevices/{deviceGUID}
managementAgent                           NoteProperty string managementAgent=mdm                                                                                                         
manufacturer                              NoteProperty string manufacturer=Microsoft Corporation                                                                                          
meid                                      NoteProperty string meid=                                                                                                                       
model                                     NoteProperty string model=Virtual Machine                                                                                                       
operatingSystem                           NoteProperty string operatingSystem=Windows                                                                                                     
osVersion                                 NoteProperty string osVersion=10.0.17763.1397                                                                                                   
partnerReportedThreatState                NoteProperty string partnerReportedThreatState=unknown                                                                                          
phoneNumber                               NoteProperty string phoneNumber=                                                                                                                
remoteAssistanceSessionErrorDetails       NoteProperty object remoteAssistanceSessionErrorDetails=null                                                                                    
remoteAssistanceSessionUrl                NoteProperty object remoteAssistanceSessionUrl=null                                                                                             
serialNumber                              NoteProperty string serialNumber={guid}                                                                              
subscriberCarrier                         NoteProperty string subscriberCarrier=                                                                                                          
totalStorageSpaceInBytes                  NoteProperty long totalStorageSpaceInBytes=135838826496                                                                                         
userDisplayName                           NoteProperty string userDisplayName={string}                                                                                                
userId                                    NoteProperty string userId={string}                                                                                 
userPrincipalName                         NoteProperty string userPrincipalName={string}                                                                                        
wiFiMacAddress                            NoteProperty string wiFiMacAddress={string}                                                                                                        
#>
