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
- 既存のECS環境にCI/CDを追加したい場合も、本リポジトリ単体でデプロイできます
- **Deploy Stageを動作させるには `aws-app` のデプロイが必要です。** `aws-app` 未デプロイの状態でパイプラインを実行すると Deploy Stage で失敗します
- ソースリポジトリは **CodeCommit版** と **GitHub版** の2択です
- IaCツールは **Terraform版** と **CloudFormation版** の2択です

> 詳細なスコープ・アーキテクチャは [docs/design.md](docs/design.md) を参照してください。

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
| 2 | [docs/setup_guide.md](docs/setup_guide.md) | CodeCommit版 接続手順。ローカルとAWSの接続設定を行う |
| 2 | [docs/setup_guide_github.md](docs/setup_guide_github.md) | GitHub版 接続手順。CodeStar Connectionsの承認手順を行う |

---

## 構築手順

### 前提条件

- AWS CLI v2 インストール済み・認証情報設定済み
- Terraform >= 1.6（Terraform版を使う場合）
- アプリインフラ（ECS / ALB 等）が別途構築済みであること

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
./deploy.sh --project-name <project_name> --region ap-northeast-1
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
│   ├── setup_guide.md             # CodeCommit版 接続セットアップ手順
│   └── setup_guide_github.md      # GitHub版 接続セットアップ手順
├── terraform/                     # Terraform 版 IaC（作成中）
│   └── modules/
│       ├── ecr/                   # ECR リポジトリ（共通）
│       ├── source-codecommit/     # CodeCommit + EventBridge（CodeCommit版）
│       ├── source-github/         # CodeStar Connections（GitHub版）
│       ├── iam/                   # 各サービス用IAMロール・ポリシー（共通）
│       └── pipeline/              # CodePipeline + CodeBuild + CodeDeploy + S3 + CloudWatch Logs（共通）
└── cloudformation/                # CloudFormation 版 IaC（作成中）
    └── stacks/
        ├── 01-ecr.yaml                # ECR リポジトリ（共通）
        ├── 02-source-codecommit.yaml  # CodeCommit版 ← どちらか一方を選択
        ├── 02-source-github.yaml      # GitHub版    ←
        ├── 03-iam.yaml                # 各サービス用IAMロール・ポリシー（共通）
        └── 04-pipeline.yaml           # CodePipeline + CodeBuild + CodeDeploy + S3 + CloudWatch Logs（共通）
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
| CodeDeploy Application | 04-pipeline | デプロイアプリケーション定義（Deployment Groupはaws-app側） |
| S3 | 04-pipeline | CodePipelineアーティファクトバケット |
| CloudWatch Logs | 04-pipeline | CodeBuildビルドログ |

---

## License

MIT License
