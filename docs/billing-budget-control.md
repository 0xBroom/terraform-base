# Automated Billing Budget Control

## 🎯 Overview

This system automatically protects your project from unexpected costs by disabling billing when spending exceeds your monthly budget limit. It monitors your project costs in real-time and takes immediate action when thresholds are crossed.

## 🏗️ Architecture Diagram

```
┌─────────────────────┐    ┌─────────────────────┐    ┌─────────────────────┐
│   Google Cloud      │    │     Pub/Sub Topic   │    │   Cloud Function    │
│   Billing Budget    │───▶│  Budget Alerts      │───▶│   Stop Billing      │
│                     │    │                     │    │                     │
└─────────────────────┘    └─────────────────────┘    └─────────────────────┘
                                                                    │
                                                                    ▼
                                                       ┌─────────────────────┐
                                                       │   Cloud Billing     │
                                                       │   API - Disable     │
                                                       │   Project Billing   │
                                                       └─────────────────────┘
```

## 🔧 How It Works

### 1. Budget Monitor
Google Cloud continuously monitors your project spending against your monthly budget limit. The budget is configured with your billing account and watches all costs in your project.

When spending reaches certain percentages of your budget (like 50%, 90%, or 100%), Google automatically sends alert messages.

### 2. Alert Processing
Budget alerts are sent to a Pub/Sub topic called `budget-notifications`. These messages contain important information like:

```json
{
  "costAmount": 85.50,
  "budgetAmount": 100.0,
  "alertThresholdExceeded": 0.9,
  "projectId": "your-project-id"
}
```

The key fields are current spending amount, your budget limit, which threshold was crossed, and which project is affected.

### 3. Automatic Response
A Cloud Function listens to these alert messages. When it receives an alert, it checks if spending has reached 100% of the budget. If yes, it immediately calls the Google Cloud Billing API to disable billing for your project.

The function uses this simple logic:
```python
if current_spending >= budget_limit:
    disable_billing_for_project()
```

## 🔐 Security

The system uses a dedicated service account with minimal permissions. It can only:
- Read your project's billing status
- Disable billing for your specific project
- Nothing else

This ensures the function cannot accidentally affect other projects or enable billing.

## 🧪 Testing the System

You can test the system manually by sending messages to the Pub/Sub topic to simulate budget alerts.

### Test Below Threshold (No Action)
```bash
# Simulate spending below budget limit
gcloud pubsub topics publish budget-notifications \
  --project=your-project-id \
  --message='{
    "costAmount": 50.0,
    "budgetAmount": 100.0,
    "alertThresholdExceeded": 0.5,
    "projectId": "your-project-id"
  }'
```

The function will log that the budget is not exceeded and take no action.

### Test Billing Disable (Over Threshold)
```bash
# Simulate spending over budget limit
gcloud pubsub topics publish budget-notifications \
  --project=your-project-id \
  --message='{
    "costAmount": 105.0,
    "budgetAmount": 100.0,
    "alertThresholdExceeded": 1.0,
    "projectId": "your-project-id"
  }'
```

**⚠️ WARNING**: This will actually disable billing if the function is working correctly.

### Re-enable billing manually
```bash
# Re-enable billing acount (needs billing admin permissions)
gcloud billing projects link proyect-name --billing-account=BILLINS_ACOUNT_NUMBER
```


## 🚨 What Happens When Triggered

When billing is disabled, all your services will immediately stop running:
- Your web applications become unavailable
- Database connections are terminated  
- All other billable services stop

## 💡 Recovery

If billing gets disabled, you need to:

1. **Re-enable billing manually** in the Google Cloud Console
2. **Increase your budget** in the configuration file if needed
3. **Wait for services to restart** (this may take a few minutes)

### Emergency Commands

Disable the automation temporarily:
```bash
# Remove the function's permission to disable billing
gcloud projects remove-iam-policy-binding your-project-id \
  --member="serviceAccount:pre-stop-billing-sa@your-project-id.iam.gserviceaccount.com" \
  --role="roles/billing.admin"
```

Re-enable billing manually:
```bash
# Link your billing account back to the project
gcloud billing projects link your-project-id \
  --billing-account=your-billing-account-id
```

## ⚙️ Configuration

The system is configured in your `settings/pre.yaml` file:

```yaml
budget:
  billing_account: "your-billing-account-id"
  amount: your-monthly-limit
  currency_code: "EUR" 
  alert_spent_percents:
    - 0.5  # Warning at 50%
    - 0.9  # Warning at 90%  
    - 1.0  # Disable at 100%
```


**⚠️ Important**: This system will completely shut down your project when the budget is exceeded. Make sure your budget is set appropriately for your expected usage.
