# Deploy an Azure API-M instance in Internal VNET mode with an Application Gateway 

# This script uses the new AZ PowerShell cmdlets
# https://docs.microsoft.com/en-us/powershell/azure/new-azureps-module-az?view=azps-1.6.0

# Login to Azure 
Connect-AzAccount

# Set subscription
$subscriptionId = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" #  GUID of target Azure subscription
Get-AzSubscription -Subscriptionid $subscriptionId | Select-AzSubscription

# Create resource group
$resGroupName = "myresourcegroup-rg" # resource group name
$location = "UK South"           # Azure region
New-AzResourceGroup -Name $resGroupName -Location $location

# Create subnet config for Application Gateway
$appgatewaysubnet = New-AzVirtualNetworkSubnetConfig -Name "appgw-subnet" -AddressPrefix "10.0.0.0/24"

# Create subnet config for API-M
$apimsubnet = New-AzVirtualNetworkSubnetConfig -Name "apim-subnet" -AddressPrefix "10.0.1.0/24"

# Create VNET and assign subnets
$vnet = New-AzVirtualNetwork -Name "myvnet-vnet" -ResourceGroupName $resGroupName -Location $location -AddressPrefix "10.0.0.0/16" -Subnet $appgatewaysubnet,$apimsubnet

# Assign subnet variables
$appgatewaysubnetdata = $vnet.Subnets[0]
$apimsubnetdata = $vnet.Subnets[1]


# ------------- Deploy API Management  ------------- #

# Create an API-M VNET object
$apimVirtualNetwork = New-AzApiManagementVirtualNetwork -SubnetResourceId $apimsubnetdata.Id

# Create an API-M service inside the VNET
$apimServiceName = "mytestapi-apim"                 # API Management service instance name (.azure-api.net suffix will be added so has to be globally unique)
$apimOrganization = "my org name"          # organization name
$apimAdminEmail = "admin@yourdomain.org" # administrator's email address
$apimService = New-AzApiManagement -ResourceGroupName $resGroupName -Location $location -Name $apimServiceName -Organization $apimOrganization -AdminEmail $apimAdminEmail -VirtualNetwork $apimVirtualNetwork -VpnType "Internal" -Sku "Developer"

# Specify cert configuration
$gatewayHostname = "api.yourdomain.org"                 # API gateway host
$portalHostname = "portal.yourdomain.org"               # API developer portal host
$gatewayCertCerPath = "C:\temp\apicert.cer" # full path to api.yourdomain.co.uk .cer file
$gatewayCertPfxPath = "C:\temp\apicert.pfx" # full path to api.yourdomain.co.uk .pfx file
$portalCertPfxPath = "C:\temp\portalcert.pfx"   # full path to portal.yourdomain.co.uk .pfx file
$gatewayCertPfxPassword = "abc123"   # password for api.yourdomain.co.uk pfx certificate
$portalCertPfxPassword = "abc123"    # password for portal.yourdomain.co.uk pfx certificate

$certPwd = ConvertTo-SecureString -String $gatewayCertPfxPassword -AsPlainText -Force
$certPortalPwd = ConvertTo-SecureString -String $portalCertPfxPassword -AsPlainText -Force

# Create and set the hostname configuration objects for the proxy and portal
$proxyHostnameConfig = New-AzApiManagementCustomHostnameConfiguration -Hostname $gatewayHostname -HostnameType Proxy -PfxPath $gatewayCertPfxPath -PfxPassword $certPwd
$portalHostnameConfig = New-AzApiManagementCustomHostnameConfiguration -Hostname $portalHostname -HostnameType Portal -PfxPath $portalCertPfxPath -PfxPassword $certPortalPwd

$apimService.ProxyCustomHostnameConfiguration = $proxyHostnameConfig
$apimService.PortalCustomHostnameConfiguration = $portalHostnameConfig
Set-AzApiManagement -InputObject $apimService # update our API-M instance


# ------------- Deploy Application Gateway  ------------- #

# Create a public IP address for the Application Gateway front-end
$publicip = New-AzPublicIpAddress -ResourceGroupName $resGroupName -name "appgw-pip" -location $location -AllocationMethod Dynamic

# Create Application Gateway configuration
# step 1 - create App GW IP config
$gipconfig = New-AzApplicationGatewayIPConfiguration -Name "gatewayIP" -Subnet $appgatewaysubnetdata

# step 2 - configure the front-end IP port for the public IP endpoint
$fp01 = New-AzApplicationGatewayFrontendPort -Name "frontend-port443" -Port 443

# step 3 - configure the front-end IP with the public IP endpoint
$fipconfig01 = New-AzApplicationGatewayFrontendIPConfig -Name "frontend1" -PublicIPAddress $publicip

# step 4 - configure certs for the App Gateway
$cert = New-AzApplicationGatewaySslCertificate -Name "apim-gw-cert01" -CertificateFile $gatewayCertPfxPath -Password $certPwd
$certPortal = New-AzApplicationGatewaySslCertificate -Name "apim-portal-cert01" -CertificateFile $portalCertPfxPath -Password $certPortalPwd

# step 5 - configure HTTP listeners for the App Gateway
$listener = New-AzApplicationGatewayHttpListener -Name "apim-gw-listener01" -Protocol "Https" -FrontendIPConfiguration $fipconfig01 -FrontendPort $fp01 -SslCertificate $cert -HostName $gatewayHostname -RequireServerNameIndication true
$portalListener = New-AzApplicationGatewayHttpListener -Name "apim-portal-listener02" -Protocol "Https" -FrontendIPConfiguration $fipconfig01 -FrontendPort $fp01 -SslCertificate $certPortal -HostName $portalHostname -RequireServerNameIndication true

# step 6 - create custom probes for API-M endpoints
$apimprobe = New-AzApplicationGatewayProbeConfig -Name "apim-gw-proxyprobe" -Protocol "Https" -HostName $gatewayHostname -Path "/status-0123456789abcdef" -Interval 30 -Timeout 120 -UnhealthyThreshold 8
$apimPortalProbe = New-AzApplicationGatewayProbeConfig -Name "apim-portal-probe" -Protocol "Https" -HostName $portalHostname -Path "/signin" -Interval 60 -Timeout 300 -UnhealthyThreshold 8

# step 7 - upload cert for SSL-enabled backend pool resources
$authcert = New-AzApplicationGatewayAuthenticationCertificate -Name "whitelistcert1" -CertificateFile $gatewayCertCerPath

# step 8 - configure HTTPs backend settings for the App Gateway
$apimPoolSetting = New-AzApplicationGatewayBackendHttpSettings -Name "apim-gw-poolsetting" -Port 443 -Protocol "Https" -CookieBasedAffinity "Disabled" -Probe $apimprobe -AuthenticationCertificates $authcert -RequestTimeout 180
$apimPoolPortalSetting = New-AzApplicationGatewayBackendHttpSettings -Name "apim-portal-poolsetting" -Port 443 -Protocol "Https" -CookieBasedAffinity "Disabled" -Probe $apimPortalProbe -AuthenticationCertificates $authcert -RequestTimeout 180

# step 9a - configure back-end IP address pool with internal IP of API-M i.e. 10.0.1.5
$apimProxyBackendPool = New-AzApplicationGatewayBackendAddressPool -Name "apimbackend" -BackendIPAddresses $apimService.PrivateIPAddresses[0]

# step 9b - create sinkpool for API-M requests we want to discard 
$sinkpool = New-AzApplicationGatewayBackendAddressPool -Name "sinkpool"

# step 10 - create a routing rule to allow external Internet access to the developer portal
$rule01 = New-AzApplicationGatewayRequestRoutingRule -Name "apim-portal-rule01" -RuleType Basic -HttpListener $portalListener -BackendAddressPool $apimProxyBackendPool -BackendHttpSettings $apimPoolPortalSetting

# step 11 - change App Gateway SKU and instances (# instances can be configured as required)
$sku = New-AzApplicationGatewaySku -Name "WAF_Medium" -Tier "WAF" -Capacity 1

# step 12 - configure WAF to be in prevention mode
$config = New-AzApplicationGatewayWebApplicationFirewallConfiguration -Enabled $true -FirewallMode "Prevention"

# Deploy the App Gateway
$appgwName = "apim-app-gw"
$appgw = New-AzApplicationGateway -Name $appgwName -ResourceGroupName $resGroupName -Location $location -BackendAddressPools $apimProxyBackendPool, $sinkpool -BackendHttpSettingsCollection $apimPoolSetting, $apimPoolPortalSetting -FrontendIpConfigurations $fipconfig01 -GatewayIpConfigurations $gipconfig -FrontendPorts $fp01 -HttpListeners $listener, $portalListener -RequestRoutingRules $rule01 -Sku $sku -WebApplicationFirewallConfig $config -SslCertificates $cert, $certPortal -AuthenticationCertificates $authcert -Probes $apimprobe, $apimPortalProbe


# ----- Add path based routing rule for /external/* API URL's only ----- #

# Get existing Application Gateway config
$appgw = Get-AzApplicationGateway -ResourceGroupName $resGroupName -Name $appgwName
$listener = Get-AzApplicationGatewayHttpListener -Name "apim-gw-listener01" -ApplicationGateway $appgw
$sinkpool = Get-AzApplicationGatewayBackendAddressPool -ApplicationGateway $appgw -Name "sinkpool"
$pool = Get-AzApplicationGatewayBackendAddressPool -ApplicationGateway $appgw -Name "apimbackend"
$poolSettings = Get-AzApplicationGatewayBackendHttpSettings -ApplicationGateway $appgw -Name "apim-gw-poolsetting"

# Add external path rule + map
$pathRule = New-AzApplicationGatewayPathRuleConfig -Name "external" -Paths "/external/*" -BackendAddressPool $pool -BackendHttpSettings $poolSettings
$appgw = Add-AzApplicationGatewayUrlPathMapConfig -ApplicationGateway $appgw -Name "external-urlpathmapconfig" -PathRules $pathRule -DefaultBackendAddressPool $sinkpool -DefaultBackendHttpSettings $poolSettings
$appgw = Set-AzApplicationGateway -ApplicationGateway $appgw

# Add external path-based routing rule
$pathmap = Get-AzApplicationGatewayUrlPathMapConfig -ApplicationGateway $appgw -Name "external-urlpathmapconfig"
$appgw = Add-AzApplicationGatewayRequestRoutingRule -ApplicationGateway $appgw -Name "apim-gw-external-rule01" -RuleType PathBasedRouting -HttpListener $listener -BackendAddressPool $Pool -BackendHttpSettings $poolSettings -UrlPathMap $pathMap
$appgw = Set-AzApplicationGateway -ApplicationGateway $appgw