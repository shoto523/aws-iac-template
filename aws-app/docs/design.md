# アプリ基盤 IaC 設計書

## 1. 目的・背景

AWS上にアプリケーションの実行基盤を即時構築できるIaCコードを提供する。  
CI/CDパイプラインは別リポジトリ（`aws-cicd`）で管理し、本リポジトリの出力値を`aws-cicd`のパラメータとして渡すことでDeploy Stageが動作する。

---

## 2. リポジトリの役割と関係

| リポジトリ | 管理内容 |
|---|---|
| `aws-app`（本リポジトリ） | アプリ基盤（ECS / ALB / CodeDeploy Deployment Group） |
| `aws-cicd` | CI/CDパイプライン（CodePipeline / CodeBuild / CodeDeploy Application） |

**構築順序：** `aws-app` を先にデプロイし、出力されるリソース名を `aws-cicd` のパラメータとして渡す。

---

## 3. スコープ定義

### 本リポジトリが管理するもの（IN SCOPE）

| コンポーネント | 説明 |
|---|---|
| ECS Cluster | コンテナの実行基盤（Fargate推奨） |
| ECS Service | アプリコンテナを常時稼働させるサービス（デプロイコントローラー: CODE_DEPLOY） |
| ECS Task Definition | コンテナの定義（イメージURI・CPU・メモリ・環境変数） |
| ALB | Blue/Greenトラフィック切替のロードバランサー |
| Target Group（Blue/Green） | Blue/Greenデプロイ用ターゲットグループ（2つ） |
| ALB Listener | 本番(80番)・テスト(8080番)のリスナー |
| CodeDeploy Application | デプロイアプリケーション定義 |
| CodeDeploy Deployment Group | ECS Blue/Greenデプロイグループ（ALB・ECS参照） |
| IAM Roles | ECS Task Execution Role / ECS Task Role / CodeDeploy Role |

### 対象外（OUT OF SCOPE）

| コンポーネント | 理由 |
|---|---|
| VPC / Subnet / Security Group | ネットワーク設計は前提条件として別途用意する |
| NAT Gateway | ネットワーク設計の一部 |
| CodePipeline / CodeBuild | `aws-cicd`側で管理 |

---

## 4. アーキテクチャ

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

## 5. インターフェース定義

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
| ネットワーク | `vpc_id` | ECS・ALBを配置するVPC ID | `vpc-xxxxxxxx` |
| ネットワーク | `public_subnet_ids` | ALBを配置するパブリックサブネットID（複数） | `subnet-xxx,subnet-yyy` |
| ネットワーク | `private_subnet_ids` | ECSタスクを配置するプライベートサブネットID（複数） | `subnet-aaa,subnet-bbb` |
| ネットワーク | `alb_security_group_id` | ALB用セキュリティグループID | `sg-xxxxxxxx` |
| ネットワーク | `ecs_security_group_id` | ECSタスク用セキュリティグループID | `sg-yyyyyyyy` |
| コンテナ | `container_name` | タスク定義のコンテナ名 | `my-app` |
| コンテナ | `container_port` | コンテナが使用するポート番号 | `80` |
| コンテナ | `ecr_repository_url` | ECRリポジトリURI（`aws-cicd`の出力値） | `123456789.dkr.ecr.ap-northeast-1.amazonaws.com/my-app` |

### 出力（`aws-cicd` へ渡す値）

| 出力名 | 説明 | aws-cicdでの用途 |
|---|---|---|
| `ecs_cluster_name` | ECSクラスター名 | `ecs_cluster_name` パラメータ |
| `ecs_service_name` | ECSサービス名 | `ecs_service_name` パラメータ |
| `codedeploy_app_name` | CodeDeployアプリ名 | `codedeploy_app_name` パラメータ |
| `codedeploy_group_name` | CodeDeployデプロイグループ名 | `codedeploy_group_name` パラメータ |
| `alb_dns_name` | ALBのDNS名 | アプリへのアクセスURL |

---

## 6. IAM設計

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

## 7. ディレクトリ構成

```
aws-app/
├── README.md
├── docs/
│   └── design.md                  ← 本ファイル
├── terraform/                     ← Terraform版
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   ├── backend.tf
│   ├── terraform.tfvars.example
│   └── modules/
│       ├── iam/                   ← ECS Task Execution / Task / CodeDeploy ロール
│       ├── alb/                   ← ALB + Target Group（Blue/Green）+ Listener
│       ├── ecs/                   ← ECS Cluster + Service + Task Definition
│       └── codedeploy/            ← CodeDeploy Deployment Group
└── cloudformation/                ← CloudFormation版
    ├── stacks/
    │   ├── 01-iam.yaml            ← ECS / CodeDeploy 用IAMロール
    │   ├── 02-alb.yaml            ← ALB + Target Group（Blue/Green）+ Listener
    │   ├── 03-ecs.yaml            ← ECS Cluster + Service + Task Definition
    │   └── 04-codedeploy.yaml     ← CodeDeploy Deployment Group
    └── deploy.sh                  ← スタックデプロイスクリプト
```

---

## 8. 前提条件

- AWS CLI v2 インストール済み・認証情報設定済み
- Terraform >= 1.6（Terraform版を使う場合）
- VPC / Subnet / Security Group が構築済みであること
- `aws-cicd` のECRデプロイが完了していること（`ecr_repository_url` が必要）

---

## 9. 設計上の決定事項

| 決定 | 理由 |
|---|---|
| CI/CDとアプリ基盤を別リポジトリで管理する | パイプラインの再利用性・ライフサイクルの違い・既存ECS環境への適用を考慮 |
| CodeDeploy Deployment GroupはAWS-APP側に含める | ALB・ECSリソースへの参照が必要なため、アプリ基盤と一体で管理すべき |
| ALBを本リポジトリに含める | ECSへの入口かつBlue/Greenの切替装置であり、ECSと一体で管理すべき |
| CodeDeploy Application + Deployment GroupをAWS-APP側に含める | ECS・ALBリソースへの参照が必要なため、アプリ基盤と一体で管理すべき |
| CloudFormationはスタックを4本に分割 | IAM → ALB → ECS → CodeDeploy の順に依存関係があるため分割 |
