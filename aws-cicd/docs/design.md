# CI/CD パイプライン IaC 設計書

## 1. 目的・背景

AWS上に**CI/CDパイプラインのみ**を即時構築できるIaCコードを提供する。  
デプロイ先となるアプリケーション基盤（ECS / ALB 等）は別リポジトリ（`aws-app`）で管理する。

---

## 2. リポジトリ分割の理由

| リポジトリ | 管理内容 |
|---|---|
| `aws-cicd`（本リポジトリ） | CI/CDパイプライン（CodePipeline / CodeBuild / ECR / S3 / IAM） |
| `aws-app` | アプリ基盤（ECS / ALB / CodeDeploy Application + Deployment Group） |

**分割する理由：**

- **再利用性** : CI/CDパイプラインは複数のアプリ環境に対して使い回せる。既存ECS環境にCI/CDを追加したいケースでも、本リポジトリ単体でデプロイ可能
- **ライフサイクルの違い** : パイプラインの設定はほぼ変わらないが、ECS / ALBはアプリの要件によって変更頻度が異なる
- **責務の分離** : CI/CDの構築とアプリ基盤の構築は独立して行える

---

## 3. Deploy Stage とアプリ基盤の依存関係

**本リポジトリのみではDeploy Stageは動作しない。**

CodePipelineのDeploy StageはCodeDeployを通じてECSにデプロイする。ECS / ALB / CodeDeploy Deployment Group が存在しない状態でパイプラインを実行すると、Deploy Stage で失敗する。

| デプロイ状態 | Source Stage | Build Stage | Deploy Stage |
|---|---|---|---|
| 本リポジトリのみデプロイ済み（アプリ参照値未設定） | ✅ | ✅（ECRへのpushまで） | ❌（ECSが存在しないため失敗） |
| `aws-app` をデプロイ済み・パラメータ設定済み | ✅ | ✅ | ✅ |
| 既存ECS連携・パラメータ設定済み | ✅ | ✅ | ✅ |

**新規ECSの場合：** 本リポジトリを先にデプロイして `ecr_repository_url` を取得し、次に `aws-app` をデプロイする（`ecr_repository_url` が必要なため）。`aws-app` の出力値を本リポジトリのパラメータにセットして再デプロイする。  
**既存ECSの場合：** `aws-app` は不要。既存リソース名を本リポジトリのパラメータに直接渡す（[詳細 → docs/qa.md](qa.md)）。

---

## 4. スコープ定義

### 本リポジトリが管理するもの（IN SCOPE）

ソース種別（CodeCommit版 / GitHub版）によって使用するコンポーネントが一部異なる。

**共通（両版で使用）**

| コンポーネント | 説明 |
|---|---|
| AWS CodePipeline | CI/CDパイプラインのオーケストレーション |
| AWS CodeBuild | ソースのビルド・テスト・Dockerイメージ生成 |
| Amazon ECR | Dockerイメージの保管リポジトリ |
| Amazon S3 | CodePipelineのアーティファクトバケット |
| IAM Roles / Policies | 各サービスの最小権限ロール |
| Amazon CloudWatch Logs | CodeBuildのビルドログ |
| buildspec.yml | CodeBuildビルド定義 |

**CodeCommit版のみ**

| コンポーネント | 説明 |
|---|---|
| AWS CodeCommit | ソースコードのリポジトリ |
| Amazon EventBridge | CodeCommitのpushイベントを検知してCodePipelineを起動するルール |

**GitHub版のみ**

| コンポーネント | 説明 |
|---|---|
| AWS CodeStar Connections | GitHubリポジトリとCodePipelineを接続するための認証機構 |

### 対象外（OUT OF SCOPE）

`aws-app` リポジトリで管理する。

| コンポーネント | 理由 |
|---|---|
| ECS Cluster / Service / Task Definition | アプリケーションの実行基盤。`aws-app`で管理 |
| ALB / Target Group / Listener | アプリケーションのトラフィック管理。`aws-app`で管理 |
| CodeDeploy Application + Deployment Group | ECS・ALBリソースへの参照が必要なため`aws-app`と一体で管理 |
| VPC / Subnet / Security Group | ネットワーク設計は前提条件として別途用意する |
| NAT Gateway | ネットワーク設計の一部 |

---

## 5. アーキテクチャ

### CodeCommit版

```
┌──────────────────────────────────────────────────────────────────┐
│  本リポジトリのスコープ（aws-cicd）                               │
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
│     └─ Deploy Stage  : CodeDeploy（Deployment Groupはaws-app側） │
│                                                                  │
│  [ECR]  ← Dockerイメージリポジトリ                               │
│  [S3]   ← アーティファクト保管                                   │
└──────────────────────────────────────────────────────────────────┘
          │ Deploy Stage
          ▼
┌──────────────────────────────────────────────────────────────────┐
│  aws-app のスコープ                                               │
│                                                                  │
│  [CodeDeploy Deployment Group]                                   │
│     └─ ECS Blue/Green デプロイ                                   │
│  [ECS Cluster / Service]                                         │
│  [ALB / Target Group（Blue/Green）]                              │
└──────────────────────────────────────────────────────────────────┘
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

## 6. インターフェース定義

本セクションのパラメータはTerraform版・CloudFormation版で共通。渡し方のみ異なる。

| IaCツール | パラメータの渡し方 |
|---|---|
| Terraform | `terraform.tfvars` に記載 |
| CloudFormation | `deploy.sh` の `--parameter-overrides` で渡す |

### 入力パラメータ（ユーザー設定値）

| 分類 | パラメータ名 | 説明 | 例 |
|---|---|---|---|
| 共通 | `project_name` | リソース名プレフィックス | `my-app` |
| 共通 | `aws_region` | デプロイ先リージョン | `ap-northeast-1` |
| ソース情報（CodeCommit版） | `codecommit_repo_name` | ソースコードを格納するCodeCommitリポジトリ名 | `my-app-repo` |
| ソース情報（CodeCommit版） | `codecommit_branch` | トリガー対象ブランチ | `main` |
| アプリ参照値 | `ecs_cluster_name` | デプロイ先ECSクラスター名（`aws-app`の出力値） | `my-app-cluster` |
| アプリ参照値 | `ecs_service_name` | デプロイ先ECSサービス名（`aws-app`の出力値） | `my-app-service` |
| アプリ参照値 | `codedeploy_app_name` | CodeDeployアプリ名（`aws-app`の出力値） | `my-app-deploy` |
| アプリ参照値 | `codedeploy_group_name` | CodeDeployデプロイグループ名（`aws-app`の出力値） | `my-app-deploy-group` |

> GitHub版を使用する場合はソース情報のパラメータが異なる（`02-source-github.yaml` / `source-github` モジュールを参照）。

### 出力

| 出力名 | 説明 | 用途 |
|---|---|---|
| `ecr_repository_url` | ECRリポジトリのURI | `aws-app`のタスク定義でimage URIとして使用 |
| `pipeline_name` | CodePipelineの名前 | 監視・運用 |
| `artifact_bucket_name` | S3バケット名 | 監視・運用 |

---

## 7. IAM設計

### source_type による条件分岐

IAM リソースは `source_type` 変数（`"codecommit"` または `"github"`）によって作成内容が変わる。

| リソース | codecommit | github |
|---|---|---|
| CodePipeline ロール（共通部分） | ✅ | ✅ |
| CodeCommit アクセスポリシー | ✅ | ❌ |
| CodeStar Connections ポリシー | ❌ | ✅ |
| EventBridge ロール | ✅ | ❌ |

**実装方法（Terraform）**: `count = var.source_type == "codecommit" ? 1 : 0` で条件付きリソース作成。

**実装方法（CloudFormation）**: `Conditions` セクションで `IsCodeCommit: !Equals [!Ref SourceType, "codecommit"]` を定義し、各リソースに `Condition:` を付与。

---

### CodePipeline実行ロール

ソース種別によって権限が異なる。

**CodeCommit版**

| 操作対象 | 必要な権限 |
|---|---|
| CodeCommit | GetBranch, GetCommit, GetRepository, GitPull |
| S3（アーティファクトバケット） | GetObject, PutObject, GetBucketVersioning |
| CodeBuild | StartBuild, BatchGetBuilds |
| CodeDeploy | CreateDeployment, GetDeployment, RegisterApplicationRevision |
| IAM | PassRole |

**GitHub版**

| 操作対象 | 必要な権限 |
|---|---|
| CodeStar Connections | UseConnection |
| S3（アーティファクトバケット） | GetObject, PutObject, GetBucketVersioning |
| CodeBuild | StartBuild, BatchGetBuilds |
| CodeDeploy | CreateDeployment, GetDeployment, RegisterApplicationRevision |
| IAM | PassRole |

### CodeBuild実行ロール

| 操作対象 | 必要な権限 |
|---|---|
| ECR | GetAuthorizationToken, PutImage, BatchCheckLayerAvailability ほか |
| S3（アーティファクトバケット） | GetObject, PutObject |
| CloudWatch Logs | CreateLogGroup, CreateLogStream, PutLogEvents |

### EventBridge実行ロール（CodeCommit版のみ）

| 操作対象 | 必要な権限 |
|---|---|
| CodePipeline | StartPipelineExecution |

---

## 8. ディレクトリ構成

```
aws-cicd/                          ← 本ドキュメントが対象とするフォルダ
├── README.md
├── buildspec.yml                  ← CodeBuildビルド定義（アプリリポジトリのルートに配置して使用）
├── docs/
│   ├── design.md                  ← 本ファイル
│   ├── buildspec_design.md        ← buildspec.yml 設計書（アプリ側で用意するファイル含む）
│   ├── setup_guide.md             ← CodeCommit版 接続セットアップ手順
│   ├── setup_guide_github.md      ← GitHub版 接続セットアップ手順
│   └── qa.md                      ← よくある質問（既存ECS連携手順など）
├── terraform/                     ← Terraform版
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   ├── backend.tf
│   ├── terraform.tfvars.example
│   └── modules/
│       ├── ecr/                   ← ECRリポジトリ（共通）
│       ├── source-codecommit/     ← CodeCommitリポジトリ + EventBridge（CodeCommit版）
│       ├── source-github/         ← CodeStar Connections（GitHub版）
│       ├── iam/                   ← 各サービス用IAMロール・ポリシー（共通）
│       └── pipeline/              ← CodePipeline + CodeBuild + S3 + CloudWatch Logs + EventBridge（共通）
└── cloudformation/                ← CloudFormation版
    ├── root.yml                   ← ネストスタック頂点（全スタックを1コマンドでデプロイ）
    └── stacks/
        ├── 01-ecr.yaml                ← ECRリポジトリ（共通）
        ├── 02-source-codecommit.yaml  ← CodeCommitリポジトリ + EventBridge（CodeCommit版）
        ├── 02-source-github.yaml      ← CodeStar Connections（GitHub版）
        ├── 03-iam.yaml                ← 各サービス用IAMロール・ポリシー（共通）
        └── 04-pipeline.yaml           ← CodePipeline + CodeBuild + S3 + CloudWatch Logs（共通）
```

> **ソース選択**: `02-source-codecommit.yaml`（CodeCommit版）と `02-source-github.yaml`（GitHub版）はどちらか一方のみデプロイする。使用しない方はデプロイ不要。Terraform版も同様に `source-codecommit/` または `source-github/` のどちらか一方のみ `main.tf` に含める。

---

## 9. スタック間の依存関係

### CloudFormation

`root.yml` がネストスタックの頂点として機能し、以下の順序で子スタックを展開する。

```
root.yml（頂点）
│
├─ [1] 01-ecr.yaml
│        └─ 出力: EcrRepositoryUrl, EcrRepositoryArn
│                       ↓
├─ [2] 02-source-codecommit.yaml または 02-source-github.yaml
│        └─ 出力: CodeCommitRepositoryName, CodeCommitRepositoryArn（codecommit版）
│                  ConnectionArn（github版）
│                       ↓
├─ [3] 03-iam.yaml
│        ├─ 入力: EcrRepositoryArn（01より）
│        │        CodeCommitRepositoryArn または ConnectionArn（02より）
│        └─ 出力: CodePipelineRoleArn, CodeBuildRoleArn, EventBridgeRoleArn
│                       ↓
└─ [4] 04-pipeline.yaml
         ├─ 入力: CodePipelineRoleArn, CodeBuildRoleArn, EventBridgeRoleArn（03より）
         │        EcrRepositoryUrl（01より）
         │        CodeCommitRepositoryName または ConnectionArn（02より）
         └─ 出力: PipelineName, ArtifactBucketName
```

> **S3 循環依存の解消**: 03-iam は S3 アーティファクトバケットの ARN を必要とするが、バケットは 04-pipeline で作成される。  
> 解決策: バケット名を `${ProjectName}-pipeline-artifacts-${AccountId}` と命名規則で固定し、03-iam のポリシーは `arn:aws:s3:::${ProjectName}-pipeline-artifacts-*` でパターン参照する。

---

### Terraform

root `main.tf` が全モジュールの呼び出し元（頂点）として機能する。`terraform apply` 1回で依存グラフを自動解決する。

```
root main.tf（頂点）
│
├─ module.ecr
│    └─ 出力: repository_url, repository_arn
│                       ↓
├─ module.source_codecommit または module.source_github（source_type で切り替え）
│    └─ 出力: repository_name, repository_arn / connection_arn
│                       ↓
├─ aws_s3_bucket（root で直接定義）← IAM との循環依存を避けるため root に置く
│    └─ 出力: bucket_arn, bucket_name
│                       ↓（ecr / source / s3 の出力が合流）
├─ module.iam
│    ├─ 入力: ecr_repository_arn, codecommit_repo_arn / connection_arn, artifact_bucket_arn
│    └─ 出力: codepipeline_role_arn, codebuild_role_arn, eventbridge_role_arn
│                       ↓
└─ module.pipeline
     ├─ 入力: 全ロール ARN（iam より）, ecr_repository_url（ecr より）
     │        source 情報（source より）, artifact_bucket_name / artifact_bucket_arn（root s3 より）
     └─ 出力: pipeline_name
```

> **S3 循環依存の解消**: module.iam は artifact_bucket_arn が必要、module.pipeline はロール ARN が必要 → 相互依存で循環する。  
> 解決策: S3 バケットを root main.tf に直接定義し、IAM と pipeline の両モジュールに渡す。

---

## 10. 前提条件

- AWS CLI v2 インストール済み・認証情報設定済み
- Terraform >= 1.6（Terraform版を使う場合）
- Deploy Stageを動作させる場合、以下いずれかを満たすこと
  - 新規ECS：`aws-app` がデプロイ済みで、出力値をパラメータに設定済みであること
  - 既存ECS：ECS / ALB / CodeDeploy Application + Deployment Group が設定済みで、パラメータに設定済みであること

---

## 11. 操作フロー

すべての構築操作はローカルPCから実行する。TerraformはローカルのCLIからAWS APIを経由してリソースを作成する。AWSコンソールは確認・手動承認の用途でのみ使用する。

| 操作の種類 | 操作場所 |
|---|---|
| terraform init / plan / apply | ローカルPC |
| 認証情報設定（aws configure） | ローカルPC |
| tfstateバケット作成（初回のみ） | ローカルPC（AWS CLI） |
| CodeStar Connections 手動承認（GitHub版のみ） | AWSコンソール |
| 構築結果の確認（任意） | AWSコンソール |

### 新規ECS構築の場合

```
[ローカルPC]                                         [AWS]
    │
    ├─① aws-cicd: terraform apply ──────────────→  ECR / CodePipeline / CodeBuild / S3 / IAM 作成
    │                  ecr_repository_url を取得 ←
    │
    ├─② aws-app:  terraform apply ──────────────→  ECS / ALB / CodeDeploy 作成
    │                  ecs_cluster_name 等を取得 ←
    │
    ├─③ aws-cicd: terraform apply（再実行） ────→  Deploy Stage 有効化
    │
    └─④ ソースリポジトリ接続
          CodeCommit版: git push（ローカル操作）→  CodeCommit
          GitHub版: 手動承認（AWSコンソール）  →  CodeStar Connections
```

### 既存ECS連携の場合

```
[ローカルPC]                                         [AWS]
    │
    ├─① aws-cicd: terraform apply ──────────────→  ECR / CodePipeline / CodeBuild / S3 / IAM 作成
    │             ※ ECS/CodeDeploy名を tfvars に設定済みのため Deploy Stage も有効
    │
    └─② ソースリポジトリ接続
          CodeCommit版: git push（ローカル操作）→  CodeCommit
          GitHub版: 手動承認（AWSコンソール）  →  CodeStar Connections
```

---

## 12. 設計上の決定事項

| 決定 | 理由 |
|---|---|
| CI/CDとアプリ基盤を別リポジトリで管理する | パイプラインの再利用性・ライフサイクルの違い・既存ECS環境への単体適用を考慮 |
| ECRはCI/CD側に含める | ECSはECRからDockerイメージをpullするため。ただしECSを使用しない場合はECRをIaCから除外しても問題ない |
| CodeDeploy Application + Deployment GroupはAWS-APP側に含める | ECS・ALBリソースへの参照が必要なため、アプリ基盤と一体で管理すべき |
| IAMを独立したスタックにする | IAMロールは他スタックの前提条件であり変更頻度が低いため分離 |
| CloudFormationはスタックを5本に分割 | ECR → ソース選択 → IAM → パイプライン の順に依存関係があるため分割 |
| CloudFormation のデプロイ方式は root.yml（ネストスタック）を使用する | 1コマンドで全スタックが展開でき、スタック間の出力→入力の受け渡しが root.yml 内で完結するため |
| S3 アーティファクトバケットは命名規則で循環依存を解消する（CloudFormation）| 03-iam と 04-pipeline の相互依存を避けるため、バケット名をパターン（`${ProjectName}-pipeline-artifacts-*`）で固定し IAM ポリシーで参照する |
| S3 アーティファクトバケットは root main.tf に直接定義する（Terraform） | module.iam と module.pipeline の循環依存を断ち切るため、S3 バケットをどちらのモジュールにも属さない root で管理する |
| buildspec.ymlはCI/CD側に含める | ビルド定義はパイプラインの設計に属する |
