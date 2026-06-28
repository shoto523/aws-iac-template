# aws-app

![AWS](https://img.shields.io/badge/AWS-232F3E?style=for-the-badge&logo=amazonwebservices&logoColor=white)
![ECS](https://img.shields.io/badge/Amazon%20ECS-FF9900?style=for-the-badge&logo=amazonaws&logoColor=white)
![Terraform](https://img.shields.io/badge/Terraform-844FBA?style=for-the-badge&logo=terraform&logoColor=white)
![CloudFormation](https://img.shields.io/badge/CloudFormation-FF9900?style=for-the-badge&logo=amazonaws&logoColor=white)
![License](https://img.shields.io/badge/License-MIT-green?style=for-the-badge)

**AWS上にアプリケーション実行基盤を即時構築するIaCコード集。**  
ECS / ALB / CodeDeploy Deployment Group を構築し、`aws-cicd` と組み合わせることでCI/CD環境が完成します。

---

## Overview

- ECS（Fargate）・ALB・CodeDeploy Deployment Group を構築します
- VPC / Subnet / Security Group は前提条件として別途用意してください
- 本リポジトリをデプロイ後、出力値を `aws-cicd` のパラメータに渡すことでDeploy Stageが動作します
- 既存のECS環境がある場合は `aws-cicd` を単体でデプロイしてください

---

## Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│  本リポジトリのスコープ（aws-app）                                │
│                                                                  │
│  [ALB]                                                           │
│     ├─ 本番リスナー（:80）  → Target Group Blue                  │
│     └─ テストリスナー（:8080）→ Target Group Green               │
│                                                                  │
│  [CodeDeploy Deployment Group]                                   │
│     └─ ECS Blue/Green切替を制御                                  │
│                                                                  │
│  [ECS Cluster]                                                   │
│     └─ [ECS Service]                                             │
│          └─ [ECS Task（コンテナ）]                               │
│               └─ ECRからDockerイメージをpull（aws-cicdが管理）   │
└──────────────────────────────────────────────────────────────────┘
          ※ VPC / Subnet / Security Group は前提条件（対象外）
```

---

## ドキュメント

| ファイル | 内容 |
|---|---|
| [docs/design.md](docs/design.md) | 設計書。スコープ・アーキテクチャ・インターフェース定義を確認する |
| [docs/resource_design.md](docs/resource_design.md) | リソース詳細設計書（Terraform版）。各AWSリソースの名前・設定値・IAM権限の詳細 |
| [docs/resource_design_cfn.md](docs/resource_design_cfn.md) | リソース詳細設計書（CloudFormation版）。スタック・パラメータ・論理ID・Outputs の詳細 |

---

## 構築手順

### 前提条件

- AWS CLI v2 インストール済み・認証情報設定済み
- Terraform >= 1.6（Terraform版を使う場合）
- **tfstate 保存用 S3 バケットが作成済みであること**（Terraform版・初回のみ）
  ```powershell
  aws s3api create-bucket `
    --bucket <your-tfstate-bucket-name> `
    --region ap-northeast-1 `
    --create-bucket-configuration LocationConstraint=ap-northeast-1
  aws s3api put-bucket-versioning `
    --bucket <your-tfstate-bucket-name> `
    --versioning-configuration Status=Enabled
  ```
- VPC / Subnet / Security Group が構築済みであること
- `aws-cicd` のECRデプロイが完了していること

### Step 1: 設計書を読む

[docs/design.md](docs/design.md) でスコープ・パラメータ・前提条件を確認します。

### Step 2: IaC をデプロイする

**Terraform の場合**

```powershell
cd terraform
cp terraform.tfvars.example terraform.tfvars
# terraform.tfvars を環境に合わせて編集

terraform init
terraform plan
terraform apply
```

**CloudFormation の場合**

```powershell
cd cloudformation
aws cloudformation deploy `
  --template-file root.yml `
  --stack-name <project_name>-app `
  --parameter-overrides ProjectName=<project_name> `
  --capabilities CAPABILITY_NAMED_IAM `
  --region ap-northeast-1
```

### Step 3: 出力値を `aws-cicd` に渡す

デプロイ後に出力される以下の値を `aws-cicd` のパラメータに設定します。

| 出力値 | aws-cicd のパラメータ |
|---|---|
| `ecs_cluster_name` | `ecs_cluster_name` |
| `ecs_service_name` | `ecs_service_name` |
| `codedeploy_app_name` | `codedeploy_app_name` |
| `codedeploy_group_name` | `codedeploy_group_name` |

---

## Directory Structure

```
aws-app/
├── README.md
├── docs/
│   └── design.md                  # 設計書
├── terraform/                     # Terraform 版 IaC（作成中）
│   └── modules/
│       ├── iam/                   # ECS Task Execution / Task / CodeDeploy ロール
│       ├── alb/                   # ALB + Target Group（Blue/Green）+ Listener
│       ├── ecs/                   # ECS Cluster + Service + Task Definition
│       └── codedeploy/            # CodeDeploy Deployment Group
└── cloudformation/                # CloudFormation 版 IaC（作成中）
    ├── root.yml                   # ネストスタック頂点（全スタックを1コマンドでデプロイ）
    └── stacks/
        ├── 01-iam.yaml            # ECS / CodeDeploy 用IAMロール
        ├── 02-alb.yaml            # ALB + Target Group（Blue/Green）+ Listener
        ├── 03-ecs.yaml            # ECS Cluster + Service + Task Definition
        └── 04-codedeploy.yaml     # CodeDeploy Deployment Group
```

---

## AWS Resources

| リソース | スタック | 説明 |
|---|---|---|
| IAM（Task Execution / Task / CodeDeploy） | 01-iam | 各サービス用最小権限ロール |
| ALB | 02-alb | Blue/Greenトラフィック切替のロードバランサー |
| Target Group（Blue/Green） | 02-alb | Blue/Greenデプロイ用ターゲットグループ（2つ） |
| ALB Listener（:80 / :8080） | 02-alb | 本番・テストリスナー |
| ECS Cluster | 03-ecs | コンテナの実行基盤 |
| ECS Service | 03-ecs | アプリコンテナを常時稼働させるサービス |
| ECS Task Definition | 03-ecs | コンテナの定義 |
| CodeDeploy Deployment Group | 04-codedeploy | ECS Blue/Greenデプロイグループ |

---

## License

MIT License
