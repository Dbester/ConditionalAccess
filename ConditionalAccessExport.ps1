<#
.SYNOPSIS
    Export all your Conditional Access Policies to json format
    
.DESCRIPTION
    You will have to create a App Registration and enter the TenantID, AppID and Secret key under the Authentication section.
    You will need deletgated Graph permissions:
    - Policy.Read.ConditionalAccess
    - Policy.Read.All
    - Directory.Read.All
    - Group.Read.Al
     
.EXAMPLE
    C:\PS> ConditionalAccessExport.ps1
    
.NOTES
    Edited by : Dirk
    Date    : 23.09.2021
    Version    : 1.4
#>

#####################################################
# Authentication # Fill in the below values 
#####################################################

$tenantID = "" # Replace this attribute with the Azure AD tenant ID
$appID = "" # Replace this variable wiht the Azure AD Application Registration ID
$secret = "" # Replace this variable with the secret

#####################################################
# Authentication Token #
#####################################################

function Get-AuthToken {
    $authuri = "https://login.microsoftonline.com/$($tenantID)/oauth2/v2.0/token"
    $body = @{
        client_id     = $appID
        scope         = "https://graph.microsoft.com/.default"
        client_secret = $secret
        grant_type    = "client_credentials"
    }
    try {
        $authResponse = Invoke-WebRequest -Method Post -Uri $Authuri -ContentType "application/x-www-form-urlencoded" -Body $body

        $ts = New-TimeSpan -Seconds ($authResponse.Content | ConvertFrom-Json).expires_in
        
        $authHeader = @{
            'Content-Type'='application/json'
            'Authorization'="Bearer " + ($authResponse.Content | ConvertFrom-Json).access_token
            'ExpiresOn'= (get-Date)+$ts
            }

        return $authHeader
        
        #return ($authResponse.Content | ConvertFrom-Json).access_token
    }
    Catch {
        Write-Host "ERROR: $($_.Error)"
        exit
    }

    #Write-host "Attempting to generate Auth token" -f Green
    #$token = Get-AuthTokenSecret

}

#region Authentication

write-host "At the start"

# Checking if authToken exists before running authentication
if($global:authToken){
    write-host "Have aUth"
    # Setting DateTime to Universal time to work in all timezones
    $DateTime = (Get-Date).ToUniversalTime()

    # If the authToken exists checking when it expires
    $TokenExpires = ($authToken.ExpiresOn.datetime - $DateTime).Minutes

        if($TokenExpires -le 0){

        write-host "Authentication Token expired" $TokenExpires "minutes ago" -ForegroundColor Yellow
        write-host

            # Defining User Principal Name if not present

            if($User -eq $null -or $User -eq ""){

            Write-Host

            }

        $global:authToken = Get-AuthToken -User $User

        }
}
else {
    $global:authToken = Get-AuthToken
}

#endregion

#####################################################
# Script Functions #
#####################################################

Function Get-ConditionalAccess(){

    
    [cmdletbinding()]
    
    $graphApiVersion = "Beta"
    $CA_resource = "conditionalAccess/policies"
        
        try {
        
        $uri = "https://graph.microsoft.com/$graphApiVersion/$($CA_resource)"
        (Invoke-RestMethod -Uri $uri -Headers $authToken -Method Get).Value
        
        }
        
        catch {
    
        $ex = $_.Exception
        $errorResponse = $ex.Response.GetResponseStream()
        $reader = New-Object System.IO.StreamReader($errorResponse)
        $reader.BaseStream.Position = 0
        $reader.DiscardBufferedData()
        $responseBody = $reader.ReadToEnd();
        Write-Host "Response content:`n$responseBody" -f Red
        Write-Error "Request to $Uri failed with HTTP Status $($ex.Response.StatusCode) $($ex.Response.StatusDescription)"
        write-host
        break
    
        }
    
    }

    
Function Export-JSONData(){

        <#
        .SYNOPSIS
        This function is used to export JSON data returned from Graph
        .DESCRIPTION
        This function is used to export JSON data returned from Graph
        .EXAMPLE
        Export-JSONData -JSON $JSON
        Export the JSON inputted on the function
        .NOTES
        NAME: Export-JSONData
        #>
        
        param (
        
        $JSON,
        $ExportPath
        
        )
        
            try {
        
                if($JSON -eq "" -or $JSON -eq $null){
        
                write-host "No JSON specified, please specify valid JSON..." -f Red
        
                }
        
                elseif(!$ExportPath){
        
                write-host "No export path parameter set, please provide a path to export the file" -f Red
        
                }
        
                elseif(!(Test-Path $ExportPath)){
        
                write-host "$ExportPath doesn't exist, can't export JSON Data" -f Red
        
                }
        
                else {
        
                $JSON1 = ConvertTo-Json $JSON -Depth 5
        
                $JSON_Convert = $JSON1 | ConvertFrom-Json
        
                $displayName = $JSON_Convert.displayName
        
                # Updating display name to follow file naming conventions - https://msdn.microsoft.com/en-us/library/windows/desktop/aa365247%28v=vs.85%29.aspx
                $DisplayName = $DisplayName -replace '\<|\>|:|"|/|\\|\||\?|\*', "_"
        
                $Properties = ($JSON_Convert | Get-Member | ? { $_.MemberType -eq "NoteProperty" }).Name
        
                    $FileName_CSV = "$DisplayName" + "_" + $(get-date -f dd-MM-yyyy-H-mm-ss) + ".csv"
                    $FileName_JSON = "$DisplayName" + "_" + $(get-date -f dd-MM-yyyy-H-mm-ss) + ".json"
        
                    $Object = New-Object System.Object
        
                        foreach($Property in $Properties){
        
                        $Object | Add-Member -MemberType NoteProperty -Name $Property -Value $JSON_Convert.$Property
        
                        }
        
                    write-host "Export Path:" "$ExportPath"
        
                    $Object | Export-Csv -LiteralPath "$ExportPath\$FileName_CSV" -Delimiter "," -NoTypeInformation -Append
                    $JSON1 | Set-Content -LiteralPath "$ExportPath\$FileName_JSON"
                    write-host "CSV created in $ExportPath\$FileName_CSV..." -f cyan
                    write-host "JSON created in $ExportPath\$FileName_JSON..." -f cyan
                    
                }
        
            }
        
            catch {
        
            $_.Exception
        
            }
        
        }


#####################################################
# Get Export Path #
#####################################################

$ExportPath = Read-Host -Prompt "Please specify a path to export the policy data to e.g. C:\IntuneOutput"

    # If the directory path doesn't exist prompt user to create the directory
    $ExportPath = $ExportPath.replace('"','')

    if(!(Test-Path "$ExportPath")){

    Write-Host
    Write-Host "Path '$ExportPath' doesn't exist, do you want to create this directory? Y or N?" -ForegroundColor Yellow

    $Confirm = read-host

        if($Confirm -eq "y" -or $Confirm -eq "Y"){

        new-item -ItemType Directory -Path "$ExportPath" | Out-Null
        Write-Host

        }

        else {

        Write-Host "Creation of directory path was cancelled..." -ForegroundColor Red
        Write-Host
        break

        }

    }

#####################################################
# Export Conditional Access Policies #
#####################################################


$CAs = Get-ConditionalAccess

foreach($CA in $CAs){

write-host "Device Configuration Policy:"$CA.state -f Yellow 
Export-JSONData -JSON $CA -ExportPath "$ExportPath"
write-host "$FileName_JSON" -f cyan

}
