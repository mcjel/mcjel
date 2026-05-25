#!/bin/bash
set -euo pipefail

# McJEL.com GCP Project + Cloud Run + Domain Setup
# Run from Mac terminal where gcloud + gh are available

PROJECT_ID="mcjel-com"
REGION="us-central1"
SERVICE="mcjel"
REPO="mcjel/mcjel"
SA_NAME="github-deploy"
SA_EMAIL="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

echo "=== 1. Create GCP Project ==="
gcloud projects create $PROJECT_ID --name="McJEL Website" || echo "Project may already exist"
gcloud config set project $PROJECT_ID

echo "=== 2. Link Billing ==="
BILLING_ID=$(gcloud billing accounts list --format="value(name)" | head -1)
gcloud billing projects link $PROJECT_ID --billing-account=$BILLING_ID

echo "=== 3. Enable APIs ==="
gcloud services enable \
  run.googleapis.com \
  cloudbuild.googleapis.com \
  iam.googleapis.com \
  iamcredentials.googleapis.com

echo "=== 4. Create Service Account ==="
gcloud iam service-accounts create $SA_NAME \
  --display-name="GitHub Actions Deploy" || echo "SA may already exist"

echo "Waiting 10s for SA propagation..."
sleep 10

echo "=== 5. Grant Permissions ==="
for ROLE in roles/run.admin roles/cloudbuild.builds.editor roles/storage.admin; do
  gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:$SA_EMAIL" \
    --role="$ROLE" \
    --quiet
done

gcloud iam service-accounts add-iam-policy-binding $SA_EMAIL \
  --member="serviceAccount:$SA_EMAIL" \
  --role="roles/iam.serviceAccountUser"

echo "=== 6. Workload Identity Federation ==="
PROJECT_NUM=$(gcloud projects describe $PROJECT_ID --format="value(projectNumber)")

gcloud iam workload-identity-pools create github-pool \
  --location="global" \
  --display-name="GitHub Pool" || echo "Pool may already exist"

gcloud iam workload-identity-pools providers create-oidc github-provider \
  --location="global" \
  --workload-identity-pool="github-pool" \
  --display-name="GitHub Provider" \
  --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository" \
  --issuer-uri="https://token.actions.githubusercontent.com" || echo "Provider may already exist"

gcloud iam service-accounts add-iam-policy-binding $SA_EMAIL \
  --role="roles/iam.workloadIdentityUser" \
  --member="principalSet://iam.googleapis.com/projects/$PROJECT_NUM/locations/global/workloadIdentityPools/github-pool/attribute.repository/$REPO"

echo "=== 7. Set GitHub Secrets ==="
WIF_PROVIDER="projects/$PROJECT_NUM/locations/global/workloadIdentityPools/github-pool/providers/github-provider"

gh secret set GCP_PROJECT_ID -R $REPO --body "$PROJECT_ID"
gh secret set WIF_PROVIDER -R $REPO --body "$WIF_PROVIDER"
gh secret set WIF_SERVICE_ACCOUNT -R $REPO --body "$SA_EMAIL"

echo "=== 8. Push Code (triggers first deploy) ==="
cd ~/PROJECTS/mcjel
git push -u origin main

echo "=== 9. Wait for deploy, then map domains ==="
echo "Waiting 120s for first deploy to complete..."
sleep 120

gcloud run domain-mappings create --service $SERVICE --domain mcjel.com --region $REGION --quiet || true
gcloud run domain-mappings create --service $SERVICE --domain www.mcjel.com --region $REGION --quiet || true

echo ""
echo "============================================"
echo "  DONE! Now update DNS records:"
echo "============================================"
echo ""
echo "  At your domain registrar (for mcjel.com):"
echo ""
echo "  TYPE   NAME    VALUE"
echo "  ----   ----    -----"
echo "  A      @       216.239.32.21"
echo "  A      @       216.239.34.21"
echo "  A      @       216.239.36.21"
echo "  A      @       216.239.38.21"
echo "  AAAA   @       2001:4860:4802:32::15"
echo "  AAAA   @       2001:4860:4802:34::15"
echo "  AAAA   @       2001:4860:4802:36::15"
echo "  AAAA   @       2001:4860:4802:38::15"
echo "  CNAME  www     ghs.googlehosted.com."
echo ""
echo "  SSL will auto-provision after DNS propagates (~15 min)."
echo "  Check status: gcloud run domain-mappings describe --domain mcjel.com --region $REGION"
echo "============================================"
