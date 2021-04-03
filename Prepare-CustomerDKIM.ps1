function Prepare-CustomerDKIM
{
    [cmdletbinding ()]
    param(
        [parameter (Mandatory)]
        [ValidateNotNullOrEmpty ()]
        [string]$CustomerTenant, # Tenant name

        [parameter (Mandatory)]
        [ValidateNotNullOrEmpty ()]
        [string]$Domain, # custom email domain on which it needs to be configured

        [parameter ()]
        [switch]$Prepare, # prepare configuration and outputs required DNS properties

        [parameter ()]
        [switch]$NoAutoDisconnect, # use to not get disconnected from Exchange Online Powershell

        [parameter ()]
        [switch]$Enable # used to enable DKIM and activate it on all outgoing emails.
    )   
    
    #region module
    Write-Verbose "Checking if module is loaded"
    if ($null -eq (Get-Module ExchangeOnlineManagement))
    {
        try
        {
            if ($PSVersionTable.PSVersion.Major -eq 7)
            {
                # PS7 does not have crytographic compatibility with PS5 libraries, breaking authentication.
                Import-Module ExchangeOnlineManagement -UseWindowsPowerShell 4>$null
            }
            else
            {
                Import-Module ExchangeOnlineManagement 4>$null
            }
        }
        catch
        {
            # small interactive prompt
            <# https://docs.microsoft.com/en-us/dotnet/api/system.management.automation.host.pshostuserinterface.promptforchoice
            ChoiceDescription is an array of System.Management.Automation.Host.ChoiceDescription (third parameter)
            [System.Management.Automation.Host.ChoiceDescription[]](
            each element being 
                [System.Management.Automation.Host.ChoiceDescription]::new(
            overloads:
            System.Management.Automation.Host.ChoiceDescription new(string label)
            System.Management.Automation.Host.ChoiceDescription new(string label, string helpMessage)
            #>
            $prompt = $Host.ui.PromptForChoice( `
                "Install PowerShell module ExchangeOnlineManagement", # caption
                "Do you want to install the module ExchangeOnlineManagement?", # message
                [System.Management.Automation.Host.ChoiceDescription[]](    # array of ChoiceDescription
                    ([System.Management.Automation.Host.ChoiceDescription]::new("&Yes",
                        "Installs the module."),
                    [System.Management.Automation.Host.ChoiceDescription]::new("&No",
                        "Does not install the module. Execution is stopped.") 
                    )),
                0 # default choice is Y.
            )
            switch ($prompt)
            {
                0
                {
                    try
                    {
                        Remove-Module ExchangeOnlineManagement -ErrorAction SilentlyContinue
                        # force TLS 1.2 as it is required by PSGallery
                        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
                        Install-Module ExchangeOnlineManagement -Scope CurrentUser -SkipPublisherCheck -Force -AcceptLicense
                    }
                    catch
                    {
                        Write-Error "could not install module"
                    } 
                }
                1 
                {
                    exit
                }
            }
        }
    }
    #endregion
    #region AUTH
    if (-not ('get-mailbox' -in (Get-Module tmp_*).ExportedCommands.keys))
    {
        try 
        {
            Write-Verbose "connecting to exchange online powershell on customer tenant $CustomerTenant"
            Connect-ExchangeOnline -DelegatedOrganization $CustomerTenant
        }
        catch
        {
            Write-Error "unable to logon to tenant $CustomerTenant"
            throw $Error[0]
        }
    }
    #endregion
    #region PREPARE
    $CurrentDKIMConfig = Get-DkimSigningConfig -Identity $Domain
    Write-Verbose "Current DKIM settings:"
    Write-Output $CurrentDKIMConfig

    if ($prepare)
    {
        $DomainDKIMConfiguration = Get-DkimSigningConfig | Where-Object Domain -Match $Domain
        # Validate existing
        if ( -not ($DomainDKIMConfiguration))
        {
            New-DkimSigningConfig -KeySize 2048 -DomainName $Domain -Enabled $false
        }
        $DNSConfig = [PSCustomObject]@{
            TTL          = "3600 or default"
            Type         = 'CNAME'
            Host1        = 'selector1._domainkey'
            Destination1 = $DomainDKIMConfiguration.Selector1CNAME
            Host2        = 'selector2._domainkey'
            Destination2 = $DomainDKIMConfiguration.Selector2CNAME
        }
        # return DNS stuff
        Write-Output "DKIM is ready. Customer now needs to update its DNS zone with the following elements:`n"
        $DNSConfig
    }
    #endregion
    #region ENABLE
    if ($Enable)
    {
        # DKIM is ready and customer has updated its DNS zone but we can't trust that
        if (((Resolve-DnsName -Type CNAME -Name selector1._domainkey.$Domain).NameHost -match 'onmicrosoft.com$') `
                -and `
            (Resolve-DnsName -Type CNAME -Name selector2._domainkey.$Domain).NameHost -match 'onmicrosoft.com$')
        {
            Write-Host -ForegroundColor Green "Customer DNS zone is correct, enabling DKIM.."
            Set-DkimSigningConfig -Identity $Domain -Enabled $true
            # Update to 2048 bits key size
            if (($DomainDKIMConfiguration.Selector1KeySize -eq 1024) `
                    -or `
                ($DomainDKIMConfiguration.Selector2KeySize -eq 1024) )
            {
                Rotate-DkimSigningConfig -KeySize 2048 -Identity $Domain
            }
        }
        else
        {
            Write-Host -ForegroundColor Red "Customer DNS zone is missing or has incorrect settings!`nDKIM can not be activated at this time"
            exit
        }
    }
    #endregion
    if (-not ($NoAutoDisconnect))
    {
        Disconnect-ExchangeOnline
    }
}