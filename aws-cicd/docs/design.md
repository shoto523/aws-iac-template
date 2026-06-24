# CI/CD パイプライン IaC 設計書

## 1. 目的・背景

AWS上に**CI/CDパイプラインのみ**を即時構築できるIaCコードを提供する。  
アプリケーションのインフラ（ECSクラスター、ALB、VPC等）は別リポジトリで管理するため、本リポジトリにはその責務を含まない。

---

## 2. スコープ定義

### 本リポジトリが管理するもの（IN SCOPE）

| コンポーネント | 説明 |
|---|---|
| AWS CodeCommit | ソースコードのリポジトリ。プッシュをトリガーにCodePipelineを起動する |
| AWS CodePipeline | CI/CDパイプラインのオーケストレーション |
| AWS CodeBuild | ソースのビルド・テスト・Dockerイメージ生成 |
| AWS CodeDeploy | ECSへのBlue/Greenデプロイ設定（アプリ本体は持たない） |
| Amazon ECR | Dockerイメージの保管リポジトリ |
| Amazon S3 | CodePipelineのアーティファクトバケット |
| IAM Roles / Policies | 各サービスの最小権限ロール |
| Amazon EventBridge | CodeCommitのpushイベントを検知してCodePipelineを起動するルール |
| Amazon CloudWatch Logs | CodeBuildのビルドログ |
| buildspec.yml（サンプル） | CodeBuildビルド定義のリファレンス |

### 別リポジトリ（`aws-app-infra`など）で管理するもの（OUT OF SCOPE）

| コンポーネント | 理由 |
|---|---|
| VPC / Subnet / Security Group | アプリ・ネットワーク設計はアプリ側の責務 |
| ECS Cluster / Service | アプリケーションの実行基盤 |
| ALB / Target Group / Listener | アプリケーションのトラフィック管理 |
| ECS Task Definition | アプリケーションのコンテナ設定 |
| NAT Gateway | ネットワーク設計の一部 |

---

## 3. アーキテクチャ

```
┌──────────────────────────────────────────────────────────────────┐
│  本リポジトリのスコープ（CI/CD Pipeline IaC）                    │
│                                                                  │
│  [CodeCommit]                                                    │
│     │ push をトリガー（EventBridge経由）                          │
│     ▼                                                            │
│  [CodePipeline]                                                  │
│     ├─ Source Stage  : CodeCommitからソース取得 → S3へ格納       │
│     ├─ Build Stage   : CodeBuild                                 │
│     │    ├─ テスト実行                                           │
│     │    ├─ Docker ビルド                                        │
│     │    └─ ECR へ push → imageDetail.json 生成                 │
│     └─ Deploy Stage  : CodeDeploy（設定のみ・ECSは別管理）       │
│          └─ appspec.yaml + taskdef.json を参照してデプロイ指示    │
│                                                                  │
│  [ECR]  ← CodeBuild が push する                                 │
│  [S3]   ← アーティファクト保管                                   │
└──────────────────────────────────────────────────────────────────┘
          │ deploy stage
          ▼
┌──────────────────────────────────────────┐
│  別リポジトリのスコープ（App Infra）     │
│                                          │
│  ECS Cluster / Service / Task Definition │
│  ALB / Target Group / Listener           │
│  VPC / Subnet / Security Group           │
└──────────────────────────────────────────┘
```

---

## 4. インターフェース定義

CI/CDパイプラインはアプリインフラ側のリソースを参照する。  
デプロイ時に**外部から渡す必要がある値**（変数・パラメータ）を明確にする。

### 入力（CI/CD側が受け取る値）

| パラメータ名 | 説明 | 例 |
|---|---|---|
| `project_name` | リソース名プレフィックス | `my-app` |
| `aws_region` | デプロイ先リージョン | `ap-northeast-1` |
| `codecommit_repo_name` | ソースコードを格納するCodeCommitリポジトリ名 | `my-app-repo` |
| `codecommit_branch` | トリガー対象ブランチ | `main` |
| `ecs_cluster_name` | デプロイ先ECSクラスター名（アプリ側で作成済み） | `my-app-cluster` |
| `ecs_service_name` | デプロイ先ECSサービス名（アプリ側で作成済み） | `my-app-service` |
| `codedeploy_app_name` | CodeDeployアプリ名（アプリ側で作成済み） | `my-app-deploy` |
| `codedeploy_group_name` | CodeDeployデプロイグループ名（アプリ側で作成済み） | `my-app-deploy-group` |

> **注**: ECS・ALB・CodeDeployのリソース自体はアプリインフラ側で作成する。  
> CI/CD側はその名前を受け取るだけ。

### 出力（CI/CD側が公開する値）

| 出力名 | 説明 | 用途 |
|---|---|---|
| `ecr_repository_url` | ECRリポジトリのURI | アプリ側のタスク定義でimage URIとして使用 |
| `pipeline_name` | CodePipelineの名前 | 監視・運用 |
| `artifact_bucket_name` | S3バケット名 | 監視・運用 |

---

## 5. IAM設計

### CodePipeline実行ロール

| 操作対象 | 必要な権限 |
|---|---|
| CodeCommit | GetBranch, GetCommit, GetRepository, GitPull |
| S3（アーティファクトバケット） | GetObject, PutObject, GetBucketVersioning |
| CodeBuild | StartBuild, BatchGetBuilds |
| CodeDeploy | CreateDeployment, GetDeployment, RegisterApplicationRevision |
| IAM | PassRole（ECSタスクロールを渡すため） |

### CodeBuild実行ロール

| 操作対象 | 必要な権限 |
|---|---|
| ECR | GetAuthorizationToken, PutImage, BatchCheckLayerAvailability ほか |
| S3（アーティファクトバケット） | GetObject, PutObject |
| CloudWatch Logs | CreateLogGroup, CreateLogStream, PutLogEvents |

---

## 6. ディレクトリ構成

```
aws-iac-template/
├── README.md
├── docs/
│   ├── design.md          ← 本ファイル
│   └── setup_guide.md     ← CodeCommit 接続セットアップ手順
├── terraform/                 ← Terraform版
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   ├── backend.tf
│   ├── terraform.tfvars.example
│   └── modules/
│       ├── ecr/               ← ECRリポジトリ（共通）
│       ├── source-codecommit/ ← CodeCommitリポジトリ + EventBridge（CodeCommit版）
│       ├── source-github/     ← CodeStar Connections（GitHub版）
│       └── pipeline/          ← CodePipeline + CodeBuild + S3 + IAM（共通）
└── cloudformation/            ← CloudFormation版
    ├── stacks/
    │   ├── 01-ecr.yaml                ← ECRリポジトリ（共通）
    │   ├── 02-source-codecommit.yaml  ← CodeCommitリポジトリ + EventBridge（CodeCommit版）
    │   ├── 02-source-github.yaml      ← CodeStar Connections（GitHub版）
    │   └── 03-pipeline.yaml           ← CodePipeline + CodeBuild + S3 + IAM（共通）
    └── deploy.sh
```

> **使い方**: `02-source-codecommit.yaml` と `02-source-github.yaml` はどちらか一方のみデプロイする。`01-ecr.yaml` と `03-pipeline.yaml` は共通。

---

## 7. 前提条件（デプロイ前に用意するもの）

本CI/CDパイプラインをデプロイする前に、以下がアプリインフラ側で構築済みであること。

| リソース | 備考 |
|---|---|
| ECS Cluster | Fargate推奨 |
| ECS Service | デプロイコントローラー: `CODE_DEPLOY` |
| ALB + Blue/Green Target Group | CodeDeployが使用するターゲットグループ |
| ALB Listener（本番:80, テスト:8080） | Blue/Green切り替えに使用 |
| CodeDeploy Application + Deployment Group | ECS Blue/Green設定済み |

---

## 8. 設計上の決定事項

| 決定 | 理由 |
|---|---|
| ECRはCI/CD側に含める | ECRはコンテナの配信インフラであり、CI/CDパイプラインの一部と判断 |
| CodeDeployのDeploymentGroupはアプリ側に含める | ALB・ECSリソースへの参照が必要なため、アプリインフラと一体で管理すべき |
| CloudFormationはスタックを2本に集約 | ECR（先行作成が必要）とパイプライン（ECRに依存）の2段階で十分 |
| buildspec.ymlはCI/CD側に含める | ビルド定義はパイプラインの設計に属する |
