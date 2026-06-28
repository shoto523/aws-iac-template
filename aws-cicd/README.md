# aws-cicd

![Terraform](https://img.shields.io/badge/Terraform-844FBA?style=for-the-badge&logo=terraform&logoColor=white)
![CloudFormation](https://img.shields.io/badge/CloudFormation-FF9900?style=for-the-badge&logo=amazonaws&logoColor=white)
![AWS](https://img.shields.io/badge/AWS-232F3E?style=for-the-badge&logo=amazonwebservices&logoColor=white)
![CodePipeline](https://img.shields.io/badge/CodePipeline-232F3E?style=for-the-badge&logo=amazonaws&logoColor=white)
![License](https://img.shields.io/badge/License-MIT-green?style=for-the-badge)

**AWS上にCI/CDパイプラインを即時構築するIaCコード集。**  
Terraform版とCloudFormation版の両方を提供します。

---

## Overview

このリポジトリは、**AWSのCI/CDパイプラインのみ**をIaCで即時構築するためのテンプレート集です。

- ソースコードの変更を検知し、Dockerイメージをビルドして ECR に push するまでを自動化します
- デプロイ先のアプリ基盤（ECS / ALB 等）は別リポジトリ（`aws-app`）で管理します
- **既存のECS環境がある場合**は `aws-app` を使わず、既存リソース名を本リポジトリのパラメータとして渡すことでDeploy Stageを動作させられます（[連携手順 → docs/qa.md](docs/qa.md)）
- **ECSを新規構築する場合**は、まず本リポジトリをデプロイして `ecr_repository_url` を取得し、次に `aws-app` をデプロイする（`ecr_repository_url` が入力値として必要なため）。`aws-app` の出力値を本リポジトリのパラメータにセットして再デプロイします
- `aws-app` も既存ECSも未接続の状態でパイプラインを実行すると、Deploy Stage で失敗します
- ソースリポジトリは **CodeCommit版** と **GitHub版** の2択です
- IaCツールは **Terraform版** と **CloudFormation版** の2択です

> 詳細なスコープ・アーキテクチャは [docs/design.md](docs/design.md) を参照してください。

---

## ソースリポジトリの選択

使用するスタック（`02-source-codecommit.yaml` または `02-source-github.yaml`）をどちらか一方選んでください。両方を同時にデプロイする必要はありません。

| | CodeCommit版 | GitHub版 |
|---|---|---|
| **向いている人** | AWSのみで完結させたい | GitHubを既に使っている |
| **使用するスタック** | `02-source-codecommit.yaml` | `02-source-github.yaml` |
| **使用するモジュール（Terraform）** | `source-codecommit/` | `source-github/` |
| **不要なファイル** | `02-source-github.yaml` / `source-github/` | `02-source-codecommit.yaml` / `source-codecommit/` |
| **追加セットアップ** | [docs/setup_guide.md](docs/setup_guide.md) | [docs/setup_guide_github.md](docs/setup_guide_github.md#step-2-github-との接続を手動承認する)（手動承認が必要） |

> **追加セットアップが必要な理由：** IaC のデプロイだけではソースリポジトリと CodePipeline の接続が完了しません。CodeCommit 版は git の認証設定、GitHub 版は CodeStar Connections の手動承認が必要です。これらを完了して初めて push 時に CodePipeline が起動します。

---

## Terraform vs CloudFormation

どちらか一方を選んで使用してください。両方を同時にデプロイする必要はありません。

| | Terraform | CloudFormation |
|---|---|---|
| **向いている人** | Terraformを既に使っている・マルチクラウド対応を見越している | AWSのみ・AWS管理コンソールで完結させたい |
| **状態管理** | tfstate ファイル（S3バックエンド推奨） | AWS が自動管理 |
| **デプロイ方法** | `terraform apply` | `deploy.sh` スクリプト |
| **必要ツール** | Terraform >= 1.6、AWS CLI v2 | AWS CLI v2 のみ |

---

## Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│  本リポジトリのスコープ（aws-cicd）                               │
│                                                                  │
│  [CodeCommit / GitHub]                                           │
│     │ push をトリガー                                             │
│     ▼                                                            │
│  [CodePipeline]                                                  │
│     ├─ Source Stage  : ソース取得 → S3へ格納                     │
│     ├─ Build Stage   : CodeBuild                                 │
│     │    ├─ テスト実行                                           │
│     │    ├─ Docker ビルド                                        │
│     │    └─ ECR へ push → imageDetail.json 生成                 │
│     └─ Deploy Stage  : CodeDeploy（Deployment Groupはaws-app側） │
│                                                                  │
│  [ECR]  ← Dockerイメージリポジトリ                               │
│  [S3]   ← アーティファクト保管                                   │
└──────────────────────────────────────────────────────────────────┘
          │ Deploy Stage
          ▼
┌──────────────────────────────────────────────────────────────────┐
│  aws-app のスコープ                                               │
│  ECS / ALB / CodeDeploy Deployment Group                         │
└──────────────────────────────────────────────────────────────────┘
```

---

## ドキュメントの読む順番

| 順番 | ファイル | 内容 |
|---|---|---|
| 1 | [docs/design.md](docs/design.md) | 設計書。スコープ・アーキテクチャ・インターフェース定義を確認する |
| 2 | [docs/terraform_guide.md](docs/terraform_guide.md) | Terraform 実行手順。tfstate バケット作成から terraform destroy まで |
| 2 | [docs/setup_guide.md](docs/setup_guide.md) | CodeCommit版 接続手順。ローカルとAWSの接続設定を行う |
| 2 | [docs/setup_guide_github.md](docs/setup_guide_github.md) | GitHub版 接続手順。CodeStar Connectionsの承認手順を行う |
| - | [docs/resource_design.md](docs/resource_design.md) | リソース詳細設計書（Terraform版）。各AWSリソースの名前・設定値・IAM権限の詳細 |
| - | [docs/resource_design_cfn.md](docs/resource_design_cfn.md) | リソース詳細設計書（CloudFormation版）。スタック・パラメータ・論理ID・Outputs の詳細 |
| - | [docs/buildspec_design.md](docs/buildspec_design.md) | buildspec.yml 設計書。アプリ側で用意するファイル（appspec.yaml・taskdef.json）の説明 |
| - | [docs/qa.md](docs/qa.md) | よくある質問。既存ECS連携手順・Deploy Stageエラー対処・用語解説など |

---

## 構築手順

### 前提条件

- AWS CLI v2 インストール済み・認証情報設定済み
- Terraform >= 1.6（Terraform版を使う場合）
- **tfstate 保存用 S3 バケットが作成済みであること**（Terraform版を使う場合・初回のみ）
  ```powershell
  # S3バケットを作成する
  # --bucket                              : バケット名（グローバルで一意な名前をつける）
  # --region                              : バケットを作成するリージョン
  # --create-bucket-configuration         : us-east-1 以外のリージョンで作成する際に必須
  aws s3api create-bucket `
    --bucket <your-tfstate-bucket-name> `
    --region ap-northeast-1 `
    --create-bucket-configuration LocationConstraint=ap-northeast-1

  # バージョニングを有効化する（tfstateの変更履歴を残すため推奨）
  # Status=Enabled : バージョニングをオンにする
  aws s3api put-bucket-versioning `
    --bucket <your-tfstate-bucket-name> `
    --versioning-configuration Status=Enabled
  ```
- Deploy Stageを動作させる場合は `aws-app` のデプロイ済み、または既存ECS / CodeDeploy が設定済みであること

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
  --stack-name <project_name>-cicd `
  --parameter-overrides ProjectName=<project_name> SourceType=codecommit `
  --capabilities CAPABILITY_NAMED_IAM `
  --region ap-northeast-1
```

### Step 3: ソースリポジトリと接続してコードを push する

**CodeCommit版の場合**  
[docs/setup_guide.md](docs/setup_guide.md) の手順に従い、ローカルと CodeCommit を接続します。

**GitHub版の場合**  
[docs/setup_guide_github.md](docs/setup_guide_github.md) の手順に従い、CodeStar Connections の承認を行います。

接続後、アプリケーションのコードを push すると CodePipeline が自動起動します。

---

## Directory Structure

```
aws-cicd/
├── README.md
├── buildspec.yml                  # CodeBuildビルド定義（アプリリポジトリのルートに配置して使用）
├── docs/
│   ├── design.md                  # 設計書（スコープ・インターフェース定義）
│   ├── terraform_guide.md         # Terraform 実行手順
│   ├── resource_design.md         # リソース詳細設計書（Terraform版）
│   ├── resource_design_cfn.md     # リソース詳細設計書（CloudFormation版）
│   ├── buildspec_design.md        # buildspec.yml 設計書
│   ├── setup_guide.md             # CodeCommit版 接続セットアップ手順
│   ├── setup_guide_github.md      # GitHub版 接続セットアップ手順
│   └── qa.md                      # よくある質問（既存ECS連携手順・用語解説など）
├── terraform/                     # Terraform 版 IaC（作成中）
│   └── modules/
│       ├── ecr/                   # ECR リポジトリ（共通）
│       ├── source-codecommit/     # CodeCommit（CodeCommit版）
│       ├── source-github/         # CodeStar Connections（GitHub版）
│       ├── iam/                   # 各サービス用IAMロール・ポリシー（共通）
│       └── pipeline/              # CodePipeline + CodeBuild + S3 + CloudWatch Logs + EventBridge（共通）
└── cloudformation/                # CloudFormation 版 IaC（作成中）
    ├── root.yml                   # ネストスタック頂点（全スタックを1コマンドでデプロイ）
    └── stacks/
        ├── 01-ecr.yaml                # ECR リポジトリ（共通）
        ├── 02-source-codecommit.yaml  # CodeCommit版 ← どちらか一方を選択
        ├── 02-source-github.yaml      # GitHub版    ←
        ├── 03-iam.yaml                # 各サービス用IAMロール・ポリシー（共通）
        └── 04-pipeline.yaml           # CodePipeline + CodeBuild + S3 + CloudWatch Logs（共通）+ EventBridge（CodeCommit版のみ）
```

---

## AWS Resources

| リソース | スタック | 説明 |
|---|---|---|
| ECR | 01-ecr | Dockerイメージリポジトリ |
| CodeCommit | 02-source-codecommit | ソースコードリポジトリ（CodeCommit版） |
| EventBridge | 02-source-codecommit | CodeCommitのpushイベントを検知してCodePipelineを起動 |
| CodeStar Connections | 02-source-github | GitHubとCodePipelineを接続する認証機構（GitHub版） |
| IAM | 03-iam | 各サービス用最小権限ロール・ポリシー |
| CodePipeline | 04-pipeline | CI/CDパイプラインのオーケストレーション |
| CodeBuild | 04-pipeline | Dockerビルド・テスト実行 |
| CodeDeploy Application + Deployment Group | aws-app | ECS・ALBへの参照が必要なためaws-app側で管理（[aws-app参照](../aws-app/README.md)） |
| S3 | 04-pipeline | CodePipelineアーティファクトバケット |
| CloudWatch Logs | 04-pipeline | CodeBuildビルドログ |

---

## License

MIT License
