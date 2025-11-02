````markdown
# 💤 How to Pause & Resume AWS Resources (Cost-Safe Guide)

This guide lets you **pause all AWS services** used in FaceApp to **avoid billing**, and later **resume exactly where you left off**.

---

## 🛑 PAUSE ALL SERVICES

### 1️⃣ Stop EC2 Instances
Stops compute usage (you’ll only pay for EBS storage).
```bash
aws ec2 stop-instances --instance-ids <your-instance-id> --region ap-south-1
````

### 2️⃣ Stop EKS Cluster

EKS control plane costs money even when idle.

```bash
eksctl delete cluster --name faceapp-cluster --region ap-south-1
```

> ⚠️ Save your YAML manifests before deleting if you plan to recreate the cluster later.

### 3️⃣ Disable or Delete Lambda Triggers

Prevents Lambda from auto-running on S3 uploads.

```bash
aws s3api put-bucket-notification-configuration \
  --bucket faceapp-bucket \
  --notification-configuration '{}'
```

### 4️⃣ Pause DynamoDB (Optional)

No direct pause option — export and delete if unused:

```bash
aws dynamodb export-table-to-point-in-time \
  --table-name cricketers_collection \
  --s3-bucket faceapp-backups
aws dynamodb delete-table --table-name cricketers_collection
```

### 5️⃣ Block S3 Uploads (to stop Rekognition Triggers)

```bash
aws s3api put-bucket-policy --bucket faceapp-bucket --policy '{"Version":"2012-10-17","Statement":[{"Effect":"Deny","Principal":"*","Action":"s3:PutObject","Resource":"arn:aws:s3:::faceapp-bucket/*"}]}'
```

### 6️⃣ (Optional) Remove Rekognition Collection

```bash
aws rekognition delete-collection --collection-id "cricketers"
```

### 7️⃣ Verify Nothing Is Running

```bash
aws ec2 describe-instances --filters "Name=instance-state-name,Values=running"
aws lambda list-functions
aws eks list-clusters
aws dynamodb list-tables
```

---

## ▶️ RESUME FROM WHERE YOU LEFT OFF

### 1️⃣ Restart EC2

```bash
aws ec2 start-instances --instance-ids <your-instance-id>
```

### 2️⃣ Recreate EKS Cluster (if deleted)

```bash
eksctl create cluster --name faceapp-cluster --region ap-south-1
kubectl apply -f deployment.yaml
```

### 3️⃣ Restore DynamoDB Table (if exported)

```bash
aws dynamodb restore-table-from-backup \
  --target-table-name cricketers_collection \
  --backup-arn <your-backup-arn>
```

### 4️⃣ Reconnect Lambda Triggers

```bash
aws s3api put-bucket-notification-configuration \
  --bucket faceapp-bucket \
  --notification-configuration file://notification.json
```

### 5️⃣ Re-enable S3 Upload Permissions

```bash
aws s3api delete-bucket-policy --bucket faceapp-bucket
```

### 6️⃣ Verify Everything Works

```bash
aws lambda invoke --function-name faceapp_func output.json
kubectl get pods -A
```

---

✅ **That’s it!**
Your AWS environment is safely paused — no compute, no triggers, minimal cost —
and can be restored in minutes when you’re ready to resume.

```
```
