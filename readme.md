# 🏏 FaceApp – Cricketers Facial Recognition (AWS + Jenkins + EKS + HTTPS)

This repository contains a **production-grade Facial Recognition Web App** that identifies cricketers using **AWS Rekognition**. It is fully automated using **Jenkins CI/CD**, deployed on **Amazon EKS**, and secured with **HTTPS (SSL)** via **AWS Certificate Manager**.

---

## 🧠 Architecture Overview

**Flow:**

```
User → HTTPS (ALB + ACM SSL) → Ingress → EKS Pods → AWS Services (S3, Rekognition, DynamoDB)
```

**Components:**

* **Frontend / Flask API** – User interface and API layer.
* **Docker** – Containerizes the Flask app.
* **AWS ECR** – Stores Docker images.
* **EKS (Kubernetes)** – Runs and scales the containers.
* **Jenkins** – Automates builds and deployments.
* **AWS Rekognition** – Detects and identifies faces.
* **S3 + DynamoDB** – Stores training images and metadata.
* **ALB + ACM** – Provides HTTPS and load balancing.
* **Prometheus + Grafana** – Optional monitoring setup.

---

## ⚙️ 1. Prerequisites

* Ubuntu EC2 instance (t3.medium or better)
* IAM user with programmatic access (Admin or EKS full access)
* Registered domain name in Route53
* AWS CLI configured

---

## 🚀 2. Environment Setup on EC2

```bash
sudo apt update -y
sudo apt install -y unzip curl git docker.io python3-pip openjdk-11-jdk
sudo systemctl enable docker
sudo systemctl start docker
sudo usermod -aG docker ubuntu
```

> Reconnect SSH after adding Docker group.

### Install AWS CLI, eksctl, kubectl

```bash
# AWS CLI
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip && sudo ./aws/install

# eksctl
curl -LO "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz"
tar -xzf eksctl_$(uname -s)_amd64.tar.gz
sudo mv eksctl /usr/local/bin

# kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin
```

### Configure AWS CLI

```bash
aws configure
# Enter your credentials
# Region: ap-south-1
# Output: json
```

---

## ☸️ 3. Create EKS Cluster

```bash
eksctl create cluster --name faceapp-cluster --region ap-south-1 --nodes 2 --node-type t3.medium
```

> Takes ~15 minutes.

---

## 🐳 4. Docker + ECR Setup

### Create ECR Repository

```bash
aws ecr create-repository --repository-name faceapp-repo --region ap-south-1
```

### Build & Push Docker Image

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
aws ecr get-login-password --region ap-south-1 | docker login --username AWS --password-stdin ${ACCOUNT_ID}.dkr.ecr.ap-south-1.amazonaws.com

docker build -t faceapp:latest .
docker tag faceapp:latest ${ACCOUNT_ID}.dkr.ecr.ap-south-1.amazonaws.com/faceapp-repo:latest
docker push ${ACCOUNT_ID}.dkr.ecr.ap-south-1.amazonaws.com/faceapp-repo:latest
```

---

## 🧩 5. Kubernetes Deployment Files

### deployment.yaml

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: faceapp-deployment
spec:
  replicas: 3
  selector:
    matchLabels:
      app: faceapp
  template:
    metadata:
      labels:
        app: faceapp
    spec:
      containers:
      - name: faceapp
        image: <ACCOUNT_ID>.dkr.ecr.ap-south-1.amazonaws.com/faceapp-repo:latest
        ports:
        - containerPort: 80
```

### service.yaml

```yaml
apiVersion: v1
kind: Service
metadata:
  name: faceapp-service
spec:
  type: LoadBalancer
  selector:
    app: faceapp
  ports:
    - port: 80
      targetPort: 80
```

Apply configurations:

```bash
kubectl apply -f deployment.yaml
kubectl apply -f service.yaml
kubectl get svc
```

---

## 🔐 6. Enable HTTPS via AWS Certificate Manager

### Request a Certificate (ACM)

1. Open **ACM Console** → Request public certificate.
2. Enter domain: `faceapp.yourdomain.com`
3. Validate via **DNS (Route53)**.
4. Copy **Certificate ARN** once validated.

---

### Install AWS Load Balancer Controller

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
eksctl utils associate-iam-oidc-provider --region ap-south-1 --cluster faceapp-cluster --approve
curl -o iam-policy.json https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/main/docs/install/iam_policy.json
aws iam create-policy --policy-name AWSLoadBalancerControllerIAMPolicy --policy-document file://iam-policy.json

eksctl create iamserviceaccount \
  --cluster faceapp-cluster \
  --namespace kube-system \
  --name aws-load-balancer-controller \
  --attach-policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/AWSLoadBalancerControllerIAMPolicy \
  --override-existing-serviceaccounts \
  --approve

helm repo add eks https://aws.github.io/eks-charts
helm repo update
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=faceapp-cluster \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller
```

### ingress.yaml

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: faceapp-ingress
  annotations:
    kubernetes.io/ingress.class: alb
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTPS":443}]'
    alb.ingress.kubernetes.io/certificate-arn: <YOUR_CERT_ARN>
    alb.ingress.kubernetes.io/ssl-redirect: '443'
spec:
  rules:
    - host: faceapp.yourdomain.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: faceapp-service
                port:
                  number: 80
```

Apply:

```bash
kubectl apply -f ingress.yaml
kubectl get ingress
```

Add CNAME in Route53 for domain → ALB DNS.

---

## 🔁 7. Jenkins CI/CD Pipeline

### Install Jenkins

```bash
curl -fsSL https://pkg.jenkins.io/debian/jenkins.io.key | sudo tee /usr/share/keyrings/jenkins-keyring.asc > /dev/null
echo deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian binary/ | sudo tee /etc/apt/sources.list.d/jenkins.list > /dev/null
sudo apt update && sudo apt install -y jenkins
sudo systemctl enable --now jenkins
sudo cat /var/lib/jenkins/secrets/initialAdminPassword
```

Access Jenkins: `http://<EC2_PUBLIC_IP>:8080`

Install Plugins: Docker, Kubernetes, AWS CLI, Git, Pipeline.

### Jenkinsfile

```groovy
pipeline {
  agent any
  environment {
    AWS_REGION = 'ap-south-1'
    ECR_REPO = '<ACCOUNT_ID>.dkr.ecr.ap-south-1.amazonaws.com/faceapp-repo'
  }
  stages {
    stage('Checkout') {
      steps {
        git 'https://github.com/<your-username>/FaceApp.git'
      }
    }
    stage('Build Docker Image') {
      steps {
        sh 'docker build -t faceapp:latest .'
      }
    }
    stage('Push to ECR') {
      steps {
        sh '''
        $(aws ecr get-login --no-include-email --region ${AWS_REGION})
        docker tag faceapp:latest ${ECR_REPO}:latest
        docker push ${ECR_REPO}:latest
        '''
      }
    }
    stage('Deploy to EKS') {
      steps {
        sh '''
        kubectl apply -f k8s/deployment.yaml
        kubectl apply -f k8s/service.yaml
        kubectl apply -f k8s/ingress.yaml
        '''
      }
    }
  }
}
```

Each commit → Jenkins → builds image → pushes to ECR → deploys to EKS 🚀

---

## 📈 8. Optional Monitoring with Prometheus & Grafana

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm install prometheus prometheus-community/kube-prometheus-stack
helm install grafana grafana/grafana
kubectl port-forward svc/grafana 3000:80
```

Open Grafana at [http://localhost:3000](http://localhost:3000)
(Default creds: `admin / prom-operator`)

---

## 🧹 9. Cleanup

```bash
eksctl delete cluster --name faceapp-cluster --region ap-south-1
aws ecr delete-repository --repository-name faceapp-repo --region ap-south-1 --force
aws rekognition delete-collection --collection-id cricketers --region ap-south-1
```

---

## ✅ Summary

| Component     | Service              | Purpose                       |
| ------------- | -------------------- | ----------------------------- |
| Web App       | Flask                | User-facing recognition app   |
| Container     | Docker               | Packages application          |
| Repository    | ECR                  | Stores container images       |
| Orchestration | EKS                  | Manages and scales containers |
| Automation    | Jenkins              | CI/CD pipeline                |
| AI            | Rekognition          | Face detection & recognition  |
| Storage       | S3 + DynamoDB        | Image storage & metadata      |
| Networking    | ALB + ACM            | HTTPS + Load Balancing        |
| Monitoring    | Prometheus + Grafana | Metrics & visualization       |

---

## 🧩 Author

**You** – DevOps Engineer ⚙️  | AWS | EKS | Jenkins | Docker | Flask

For educational and enterprise-grade deployment reference.

---
