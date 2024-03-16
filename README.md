# GenAITicketing
[![Deploy To Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fclarenceb%2FGenAITicketing%2Fapitoazdo%2Fdeploy%2Fdeploy.generated.json)

## Overview

This is a sample application that demonstrates how to create a simple ticketing system that allows users to submit support requests via freeform e-mail and have them automatically converted into tickets in a ticketing system. The application uses Logic Apps (Standard) for the workflow process and leverages Azure OpenAI (gpt-35-turbo-16k) to generate a structured JSON payload from the e-mail contents.  The JSON payload can then be used to integrate with ticketing systems such as ServiceNow, Jira, or any other system that accepts JSON payloads.  This sample uses Azure DevOps with custom fields on the Bug work item type.

The workflow `SupportTicketing/workflow.json` accepts an email as JSON via a HTTP API call in the form:

```json
{
    "from": "Margaret Wilson",
    "sent": "Thursday, November 9, 2023 1:09:17 PM",
    "to": "Support Mailbox <supportmailbox@SupportMailBox123.onmicrosoft.com>",
    "subject": "Web Issue",
    "content": "<email-body-with-the-support-request-details>"
}
```

You can also update the workflow to use a email trigger instead of a HTTP trigger, for example, the Outlook connector.

![Architecture Diagram](media/diagram.png)

## Setup Azure DevOps process and project

TODO

## Deployment

Click the **Deploy to Azure** button above to deploy the solution to your Azure subscription.

Alternatively, you can deploy the solution from the CLI:

```ps1
# Optional: Generate the deployment ARM template for use with GitHub "Deploy to Azure" button
.\generate.ps1

az login
az group create --name <resource-group-name> --location <location>
az deployment group create --resource-group <resource-group-name> --template-file deploy\infra\deploy.bicep

cd logicapps/
del logicapps.zip
zip -r logicapps.zip . -x *local.settings.json -x *azureconfig.json
az functionapp deploy --resource-group <resource-group-name> --name ticket-logicappstd --src-path logicapps.zip --type zip
```

Create a file `azureconfig.json` with the following content:

```json
{
    "WORKFLOWS_SUBSCRIPTION_ID": "<your-sub>",
    "WORKFLOWS_RESOURCE_GROUP_NAME": "<your-rg>",
    "WORKFLOWS_LOCATION_NAME": "<you-location>",
    "openAIKey": "<your-aoai-key>",
    "openAIEndpoint": "https://<your-aoai>.openai.azure.com/",
    "visualstudioteamservices-connectionKey": "<jwt-auth-token>",
    "azdoConnectionRuntimeUrl": "<your-azdoConnectionRuntimeUrl>",
    "devopsOrganisation": "<your-org>",
    "devopsProject": "<your-project>"
}
```

Apply the app settings file:

```sh
az webapp config appsettings set -g <resource-group-name> -n ticket-logicappstd --settings @azureconfig.json
```
