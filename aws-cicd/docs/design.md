# CI/CD パイプライン IaC 設計書

## 1. 目的・背景

AWS上に**CI/CD環境をまるごと**即時構築できるIaCコードを提供する。  
CI/CDパイプライン（CodePipeline / CodeBuild / CodeDeploy）からデプロイ先のECSインフラ（ECS Cluster / Service / ALB）まで含め、このリポジトリ単体でCI/CD環境が完成する。

既存のECSインフラがある場合はECS構築をスキップし、既存リソース名をパラメータとして渡すことで接続できる。  
VPC / Subnet / Security Group はネットワーク設計として前提条件とし、本リポジトリの対象外とする。

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
| AWS CodeDeploy Application | デプロイアプリケーション定義 |
| AWS CodeDeploy Deployment Group | ECS Blue/Greenデプロイグループ（ALB・ECS参照） |
| Amazon ECR | Dockerイメージの保管リポジトリ |
| Amazon S3 | CodePipelineのアーティファクトバケット |
| IAM Roles / Policies | 各サービスの最小権限ロール |
| Amazon CloudWatch Logs | CodeBuildのビルドログ |
| buildspec.yml | CodeBuildビルド定義 |
| ECS Cluster | コンテナの実行基盤（新規作成 or 既存利用） |
| ECS Service | アプリコンテナを常時稼働させるサービス（デプロイコントローラー: CODE_DEPLOY） |
| ECS Task Definition | コンテナの定義（イメージURI・CPU・メモリ・環境変数） |
| ALB | Blue/Greenトラフィック切替のロードバランサー |
| Target Group (Blue/Green) | Blue/Greenデプロイ用ターゲットグループ（2つ） |
| ALB Listener | 本番(80番)・テスト(8080番)のリスナー |

> 既存のECSインフラがある場合は ECS Cluster / Service / ALB 等の作成をスキップし、既存リソース名をパラメータとして渡す。

**CodeCommit版のみ**

| コンポーネント | 説明 |
|---|---|
| AWS CodeCommit | ソースコードのリポジトリ。プッシュをトリガーにCodePipelineを起動する |
| Amazon EventBridge | CodeCommitのpushイベントを検知してCodePipelineを起動するルール |

**GitHub版のみ**

| コンポーネント | 説明 |
|---|---|
| AWS CodeStar Connections | GitHubリポジトリとCodePipelineを接続するための認証機構 |

### 対象外（OUT OF SCOPE）

| コンポーネント | 理由 |
|---|---|
| VPC / Subnet / Security Group | ネットワーク設計は前提条件として別途用意する |
| NAT Gateway | ネットワーク設計の一部 |

---

## 3. アーキテクチャ

### CodeCommit版

```
┌──────────────────────────────────────────────────────────────────┐
│  本リポジトリのスコープ                                           │
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
│     └─ Deploy Stage  : CodeDeploy → ECS Blue/Green デプロイ      │
│                                                                  │
│  [ECR]  ← Dockerイメージリポジトリ                               │
│  [S3]   ← アーティファクト保管                                   │
│  [ECS Cluster / Service]  ← デプロイ先（新規作成 or 既存利用）   │
│  [ALB / Target Group]     ← Blue/Greenトラフィック切替           │
└──────────────────────────────────────────────────────────────────┘
          │ ※VPC / Subnet / Security Group は前提条件（対象外）
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
| ECS新規作成時 | `vpc_id` | ECS・ALBを配置するVPC ID | `vpc-xxxxxxxx` |
| ECS新規作成時 | `subnet_ids` | ECSタスクを配置するサブネットID（複数可） | `subnet-xxx,subnet-yyy` |
| ECS新規作成時 | `container_name` | タスク定義のコンテナ名 | `my-app` |
| ECS新規作成時 | `container_port` | コンテナが使用するポート番号 | `80` |
| ECS既存利用時 | `ecs_cluster_name` | 既存ECSクラスター名 | `my-app-cluster` |
| ECS既存利用時 | `ecs_service_name` | 既存ECSサービス名 | `my-app-service` |
| ECS既存利用時 | `codedeploy_app_name` | 既存CodeDeployアプリ名 | `my-app-deploy` |
| ECS既存利用時 | `codedeploy_group_name` | 既存CodeDeployデプロイグループ名 | `my-app-deploy-group` |

> GitHub版を使用する場合はソース情報のパラメータが異なる（`02-source-github.yaml` / `source-github` モジュールを参照）。

### 出力

| 出力名 | 説明 | 用途 |
|---|---|---|
| `ecr_repository_url` | ECRリポジトリのURI | タスク定義のイメージURIとして使用 |
| `pipeline_name` | CodePipelineの名前 | 監視・運用 |
| `artifact_bucket_name` | S3バケット名 | 監視・運用 |
| `ecs_cluster_name` | ECSクラスター名（新規作成時） | 運用・確認 |
| `ecs_service_name` | ECSサービス名（新規作成時） | 運用・確認 |
| `alb_dns_name` | ALBのDNS名（新規作成時） | アプリへのアクセスURL |

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

### ECS Task Execution ロール

ECSがコンテナ起動時に使用するロール。

| 操作対象 | 必要な権限 |
|---|---|
| ECR | GetAuthorizationToken, BatchGetImage, GetDownloadUrlForLayer |
| CloudWatch Logs | CreateLogGroup, CreateLogStream, PutLogEvents |

### ECS Task ロール

コンテナ内のアプリが使用するロール。アプリの要件に応じて権限を追加する。

| 操作対象 | 必要な権限 |
|---|---|
| （アプリ依存） | アプリが使用するAWSサービスに応じて設定 |

### CodeDeploy 実行ロール

| 操作対象 | 必要な権限 |
|---|---|
| ECS | DescribeServices, UpdateService, RegisterTaskDefinition ほか |
| ALB | DescribeTargetGroups, ModifyListener, ModifyRule ほか |
| IAM | PassRole（ECSタスクロールを渡すため） |
| S3（アーティファクトバケット） | GetObject |

---

## 6. ディレクトリ構成

```
aws-cicd/                          ← 本ドキュメントが対象とするフォルダ
├── README.md
├── buildspec.yml                  ← CodeBuildビルド定義（アプリリポジトリのルートに配置して使用）
├── docs/
│   ├── design.md                  ← 本ファイル
│   ├── setup_guide.md             ← CodeCommit版 接続セットアップ手順
│   └── setup_guide_github.md      ← GitHub版 接続セットアップ手順
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
│       ├── iam/                   ← 各サービス用IAMロール・ポリシー（共通）
│       ├── pipeline/              ← CodePipeline + CodeBuild + CodeDeploy + S3 + CloudWatch Logs（共通）
│       └── ecs/                   ← ECS Cluster + Service + ALB + CodeDeploy設定（新規作成時のみ）
└── cloudformation/                ← CloudFormation版
    ├── stacks/
    │   ├── 01-ecr.yaml                ← ECRリポジトリ（共通）
    │   ├── 02-source-codecommit.yaml  ← CodeCommitリポジトリ + EventBridge（CodeCommit版）
    │   ├── 02-source-github.yaml      ← CodeStar Connections（GitHub版）
    │   ├── 03-iam.yaml                ← 各サービス用IAMロール・ポリシー（共通）
    │   ├── 04-pipeline.yaml           ← CodePipeline + CodeBuild + CodeDeploy + S3 + CloudWatch Logs（共通）
    │   └── 05-ecs.yaml                ← ECS Cluster + Service + ALB + CodeDeploy設定（新規作成時のみ）
    └── deploy.sh                  ← スタックデプロイスクリプト（環境変数をここで渡す）
```

> **使い方**: `02-source-codecommit.yaml` と `02-source-github.yaml` はどちらか一方のみデプロイする。`05-ecs.yaml` は新規ECS作成時のみデプロイし、既存ECS利用時はスキップする。

---

## 7. 前提条件（デプロイ前に用意するもの）

### デプロイパターン

| パターン | 手順 | 備考 |
|---|---|---|
| ECSを新規作成する | 全スタック（01〜05）をデプロイ | フルCI/CD環境が一括構築される |
| 既存ECSを利用する | 01〜04のみデプロイ。既存リソース名をパラメータに渡す | 05-ecs.yaml はスキップ |

### 前提条件（共通）

| リソース | 備考 |
|---|---|
| VPC | ECS・ALBを配置するVPC |
| Subnet（パブリック + プライベート） | ALBはパブリック、ECSタスクはプライベート推奨 |
| Security Group | ALB用・ECSタスク用をそれぞれ用意 |

### 既存ECS利用時に必要なもの

| リソース | 備考 |
|---|---|
| ECS Cluster | Fargate推奨 |
| ECS Service | デプロイコントローラー: `CODE_DEPLOY` |
| ALB + Blue/Green Target Group | CodeDeployが使用するターゲットグループ（2つ） |
| ALB Listener（本番:80, テスト:8080） | Blue/Green切り替えに使用 |
| CodeDeploy Application + Deployment Group | ECS Blue/Green設定済み |

---

## 8. 設計上の決定事項

| 決定 | 理由 |
|---|---|
| ECSを本リポジトリに含める | ECSが揃って初めてCI/CDが完成するため。パイプラインとデプロイ先は一体で管理すべき |
| 既存ECSに対応する | 05-ecs.yamlをスキップし既存リソース名をパラメータで渡すことで既存ECS環境にも接続できる |
| ECRはECS使用を前提として含める | ECSはECRからDockerイメージをpullするため。ECSを使用しない場合はECRをIaCから除外しても問題ない |
| IAMを独立したスタックにする | IAMロールは他スタックの前提条件であり変更頻度が低いため分離。ロール変更がパイプラインスタックに影響しない |
| CloudFormationはスタックを6本に分割 | ECR → ソース選択 → IAM → パイプライン → ECS の順に依存関係があるため分割。既存ECS利用時は05-ecs.yamlをスキップ可能 |
| buildspec.ymlはCI/CD側に含める | ビルド定義はパイプラインの設計に属する |
