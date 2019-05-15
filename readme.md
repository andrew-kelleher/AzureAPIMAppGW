**Integrate API Management in an internal VNET with Application Gateway**

# Scenario
Azure's API Management service provides the ability to abstract backend services and present them as a set of easily consumable API's via a single HTTPs endpoint.

Some organisations require the ability to publish some API's externally to the public Internet, whilst keeping some API's private for internal consumption only.

It's possible to enable this scenario by deploying API Management into an internal Azure virtual network and only publishing API's externally that match a specific URL pattern.

# Deployment
This PowerShell script deploys - 

- Azure API Management in Internal VNET mode
- Azure Application Gateway

The script also configures path-based routing rules within the App Gateway to allow public access to any API's hosted with a base https://api.yourdomain.org/external/ URL.

Full walkthrough and further background is [here](https://medium.com/azure-architects/azure-api-management-and-application-gateway-integration-a31fde80f3db) on the Azure Architects blog.

Original Microsoft architecture and documentation is [here](https://docs.microsoft.com/en-us/azure/api-management/api-management-howto-integrate-internal-vnet-appgateway#--overview) 
