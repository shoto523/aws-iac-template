# CI/CD パイプライン IaC 設計書

## 1. 目的・背景

AWS上に**CI/CDパイプラインのみ**を即時構築できるIaCコードを提供する。  
アプリケーションのインフラ（ECSクラスター、ALB、VPC等）は別リポジトリで管理するため、本リポジトリにはその責務を含まない。

---

## 2. スコープ定義

### 本リポジトリが管理するもの（IN SCOPE）

ソース種別（CodeCommit版 / GitHub版）によって使用するコンポーネントが一部異なる。

> **コンポーネント**とは、システムを構成する個々のAWSサービス（機能単位）のこと。本IaCでは複数のAWSサービスを組み合わせてCI/CDパイプラインを構成するため、各サービスを「コンポーネント」と呼ぶ。

**共通（両版で使用）**

| コンポーネント | 説明 |
|---|---|
| AWS CodePipeline | CI/CDパイプラインのオーケストレーション |
| AWS CodeBuild | ソースのビルド・テスト・Dockerイメージ生成 |
| AWS CodeDeploy | ECSへのBlue/Greenデプロイ設定（アプリ本体は持たない） |
| Amazon ECR | Dockerイメージの保管リポジトリ |
| Amazon S3 | CodePipelineのアーティファクトバケット |
| IAM Roles / Policies | 各サービスの最小権限ロール |
| Amazon CloudWatch Logs | CodeBuildのビルドログ |
| buildspec.yml（サンプル） | CodeBuildビルド定義のリファレンス |

**CodeCommit版のみ**

| コンポーネント | 説明 |
|---|---|
| AWS CodeCommit | ソースコードのリポジトリ。プッシュをトリガーにCodePipelineを起動する |
| Amazon EventBridge | CodeCommitのpushイベントを検知してCodePipelineを起動するルール |

**GitHub版のみ**

| コンポーネント | 説明 |
|---|---|
| AWS CodeStar Connections | GitHubリポジトリとCodePipelineを接続するための認証機構 |

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

### CodeCommit版

```
┌──────────────────────────────────────────────────────────────────┐
│  本IaCのスコープ（CI/CD Pipeline IaC）                           │
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

### GitHub版

CodeCommit版との差分のみ記載する。

```
[GitHub リポジトリ]
   │ push をトリガー（CodeStar Connections経由）
   ▼
[CodePipeline]  ← 以降はCodeCommit版と同じ
```

> EventBridgeは不要。CodeStar ConnectionsがGitHubのWebhookを受け取り、CodePipelineを直接起動する。

---

## 4. インターフェース定義

本IaCはテンプレートとして提供する。デプロイ時に**ユーザーが自分の環境に合わせて設定する変数（環境変数）**を以下に明示する。

- Terraform版: `terraform.tfvars` に記載する
- CloudFormation版: スタックデプロイ時のパラメータとして渡す

### 入力パラメータ（ユーザー設定値）

| 分類 | パラメータ名 | 説明 | 例 |
|---|---|---|---|
| 共通 | `project_name` | リソース名プレフィックス | `my-app` |
| 共通 | `aws_region` | デプロイ先リージョン | `ap-northeast-1` |
| ソース情報（CodeCommit版） | `codecommit_repo_name` | ソースコードを格納するCodeCommitリポジトリ名 | `my-app-repo` |
| ソース情報（CodeCommit版） | `codecommit_branch` | トリガー対象ブランチ | `main` |
| アプリ参照値 | `ecs_cluster_name` | デプロイ先ECSクラスター名（アプリ側で作成済み） | `my-app-cluster` |
| アプリ参照値 | `ecs_service_name` | デプロイ先ECSサービス名（アプリ側で作成済み） | `my-app-service` |
| アプリ参照値 | `codedeploy_app_name` | CodeDeployアプリ名（アプリ側で作成済み） | `my-app-deploy` |
| アプリ参照値 | `codedeploy_group_name` | CodeDeployデプロイグループ名（アプリ側で作成済み） | `my-app-deploy-group` |

> **注1**: 「アプリ参照値」はECS・ALB・CodeDeployのリソース名をアプリインフラ側から受け取る値。CI/CD側でリソースを作成するわけではない。  
> **注2**: GitHub版を使用する場合はソース情報のパラメータが異なる（`02-source-github.yaml` / `source-github` モジュールを参照）。

### 出力（CI/CD側が公開する値）

| 出力名 | 説明 | 用途 |
|---|---|---|
| `ecr_repository_url` | ECRリポジトリのURI | アプリ側のタスク定義でimage URIとして使用 |
| `pipeline_name` | CodePipelineの名前 | 監視・運用 |
| `artifact_bucket_name` | S3バケット名 | 監視・運用 |

---

## 5. IAM設計

### CodePipeline実行ロール

ソース種別によって権限が異なる。

**CodeCommit版**

| 操作対象 | 必要な権限 |
|---|---|
| CodeCommit | GetBranch, GetCommit, GetRepository, GitPull |
| S3（アーティファクトバケット） | GetObject, PutObject, GetBucketVersioning |
| CodeBuild | StartBuild, BatchGetBuilds |
| CodeDeploy | CreateDeployment, GetDeployment, RegisterApplicationRevision |
| IAM | PassRole（ECSタスクロールを渡すため） |

**GitHub版**

| 操作対象 | 必要な権限 |
|---|---|
| CodeStar Connections | UseConnection（GitHubとの接続を使用するため） |
| S3（アーティファクトバケット） | GetObject, PutObject, GetBucketVersioning |
| CodeBuild | StartBuild, BatchGetBuilds |
| CodeDeploy | CreateDeployment, GetDeployment, RegisterApplicationRevision |
| IAM | PassRole（ECSタスクロールを渡すため） |

> CodeCommit権限はGitHub版では不要。代わりにCodeStar Connectionsの `UseConnection` 権限が必要。

### CodeBuild実行ロール

ソース種別に関わらず共通。

| 操作対象 | 必要な権限 |
|---|---|
| ECR | GetAuthorizationToken, PutImage, BatchCheckLayerAvailability ほか |
| S3（アーティファクトバケット） | GetObject, PutObject |
| CloudWatch Logs | CreateLogGroup, CreateLogStream, PutLogEvents |

---

## 6. ディレクトリ構成

```
aws-cicd/                          ← 本ドキュメントが対象とするフォルダ
├── README.md
├── docs/
│   ├── design.md                  ← 本ファイル
│   └── setup_guide.md             ← CodeCommit 接続セットアップ手順
├── terraform/                     ← Terraform版
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   ├── backend.tf
│   ├── terraform.tfvars.example   ← ユーザーが環境変数を記載するファイル（要コピー・編集）
│   └── modules/
│       ├── ecr/                   ← ECRリポジトリ（共通）
│       ├── source-codecommit/     ← CodeCommitリポジトリ + EventBridge（CodeCommit版）
│       ├── source-github/         ← CodeStar Connections（GitHub版）
│       └── pipeline/              ← CodePipeline + CodeBuild + S3 + IAM（共通）
└── cloudformation/                ← CloudFormation版
    ├── stacks/
    │   ├── 01-ecr.yaml                ← ECRリポジトリ（共通）
    │   ├── 02-source-codecommit.yaml  ← CodeCommitリポジトリ + EventBridge（CodeCommit版）
    │   ├── 02-source-github.yaml      ← CodeStar Connections（GitHub版）
    │   └── 03-pipeline.yaml           ← CodePipeline + CodeBuild + S3 + IAM（共通）
    └── deploy.sh                  ← スタックデプロイスクリプト（環境変数をここで渡す）
```

> **使い方**: `02-source-codecommit.yaml` と `02-source-github.yaml` はどちらか一方のみデプロイする。`01-ecr.yaml` と `03-pipeline.yaml` は共通。

---

## 7. 前提条件（デプロイ前に用意するもの）

### 段階的なデプロイについて

本IaCは**ECSを構築していない状態でも先行デプロイ可能**。ただし、ECSが未構築の場合はDeploy Stageが機能しない。

| デプロイ段階 | 使用可能な機能 | 備考 |
|---|---|---|
| ECR + パイプラインのみ先行デプロイ | Source Stage・Build Stage（ECRへのpushまで） | Deploy Stageはアプリ参照値がないため機能しない |
| アプリインフラ（ECS等）も揃った状態 | 全Stage（Source → Build → Deploy） | フルCI/CD稼働 |

### アプリインフラ側で用意するもの（Deploy Stage を使う場合）

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
| CloudFormationはスタックを4本に分割 | ECR（先行作成）→ ソース選択（CodeCommit版 or GitHub版）→ パイプライン の順に依存関係があるため分割。ソース種別をスタック差し替えで切り替え可能にする |
| buildspec.ymlはCI/CD側に含める | ビルド定義はパイプラインの設計に属する |
