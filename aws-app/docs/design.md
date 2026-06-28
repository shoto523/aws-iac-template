# アプリ基盤 IaC 設計書

## 1. 目的・背景

AWS上にアプリケーションの実行基盤を即時構築できるIaCコードを提供する。  
CI/CDパイプラインは別リポジトリ（`aws-cicd`）で管理し、本リポジトリの出力値を`aws-cicd`のパラメータとして渡すことでDeploy Stageが動作する。

---

## 2. リポジトリの役割と関係

| リポジトリ | 管理内容 |
|---|---|
| `aws-app`（本リポジトリ） | アプリ基盤（ECS / ALB / CodeDeploy Deployment Group） |
| `aws-cicd` | CI/CDパイプライン（CodePipeline / CodeBuild / ECR / S3 / IAM） |

**構築順序：** `aws-cicd` を先にデプロイして `ecr_repository_url` を取得 → 本リポジトリをデプロイ → 出力されるリソース名を `aws-cicd` のパラメータにセットして再デプロイ。

---

## 3. スコープ定義

### 本リポジトリが管理するもの（IN SCOPE）

| コンポーネント | 説明 |
|---|---|
| ECS Cluster | コンテナの実行基盤（Fargate推奨） |
| ECS Service | アプリコンテナを常時稼働させるサービス（デプロイコントローラー: CODE_DEPLOY） |
| ECS Task Definition | コンテナの定義（イメージURI・CPU・メモリ）。**コンテナ環境変数はアプリリポジトリの `taskdef.json` で管理（IaCのスコープ外）** |
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

### 4-1. 全体構成図（スコープ外含む）

```
インターネット
     │
     ▼
┌─────────────────────────────────────────────────────────────────┐
│  VPC（※スコープ外・事前に作成）                                  │
│  例: 10.0.0.0/16                                                │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  パブリックサブネット  AZ-a（例:10.0.1.0/24）             │  │
│  │                       AZ-c（例:10.0.2.0/24）  ※スコープ外│  │
│  │                                                          │  │
│  │  ┌────────────────────────────────┐  ┌───────────────┐  │  │
│  │  │  ALB（★ aws-app 管理）         │  │  NAT Gateway  │  │  │
│  │  │  :80  → Target Group Blue      │  │  ※スコープ外  │  │  │
│  │  │  :8080 → Target Group Green    │  └───────┬───────┘  │  │
│  │  └─────────────┬──────────────────┘          │          │  │
│  └────────────────┼──────────────────────────────┼──────────┘  │
│                   │ トラフィック制御               │ outbound     │
│  ┌────────────────┼──────────────────────────────┼──────────┐  │
│  │  プライベートサブネット  AZ-a（例:10.0.11.0/24）│          │  │
│  │                         AZ-c（例:10.0.12.0/24）※スコープ外│  │
│  │                   │                            │          │  │
│  │  ┌────────────────▼───────────────────────┐   │          │  │
│  │  │  ECS Cluster（★ aws-app 管理）          │───┘          │  │
│  │  │    ECS Service                          │              │  │
│  │  │      ECS Task（Fargate / awsvpc）       │              │  │
│  │  └─────────────────────────────────────────┘              │  │
│  └───────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
         │ NAT Gateway 経由（イメージpull・ログ送信）
         ▼
  ┌─────────────────────────────────────────────────────┐
  │  ECR（★ aws-cicd 管理）  ← Docker イメージ保管      │
  │  CloudWatch Logs（★ aws-app 管理）← コンテナログ    │
  └─────────────────────────────────────────────────────┘

★ = このテンプレートのスコープ（aws-cicd / aws-app）
※ = スコープ外（事前に用意が必要）
```

> **NAT Gateway が必要な理由**  
> ECS タスクはプライベートサブネットに配置されるため、ECR からのイメージ pull や CloudWatch Logs へのログ送信にインターネット経由のアウトバウンド通信が必要です。  
> NAT Gateway はパブリックサブネットに 1 つ以上配置してください。

### 4-2. セキュリティグループの設定例（スコープ外）

| SG | インバウンド | アウトバウンド |
|---|---|---|
| ALB 用 SG | 0.0.0.0/0 → :80, :8080 | すべて許可 |
| ECS タスク用 SG | ALB 用 SG → `container_port` | すべて許可（NAT GW 経由） |

### 4-3. CI/CD フロー

```
開発者
  │ push
  ▼
CodeCommit または GitHub（★ aws-cicd 管理）
  │（EventBridge または CodeStar Connections で検知）
  ▼
CodePipeline（★ aws-cicd 管理）
  ├─ Source Stage：ソースコードを取得
  ├─ Build Stage ：CodeBuild で Docker イメージをビルド → ECR へ push
  └─ Deploy Stage：CodeDeploy で ECS Blue/Green デプロイ実行
                       ↓
              ALB がトラフィックを Green（新バージョン）へ切替
              5分後に Blue（旧バージョン）のタスクを終了
```

---

## 5. インターフェース定義

本セクションのパラメータはTerraform版・CloudFormation版で共通。渡し方のみ異なる。

| IaCツール | パラメータの渡し方 |
|---|---|
| Terraform | `terraform.tfvars` に記載 |
| CloudFormation | `root.yml` のパラメータ（`Parameters` セクション）で渡す |

### Terraform のパラメータ入力挙動

デフォルト値のないパラメータは `terraform.tfvars` を用意しない場合、`terraform apply` 時にターミナルで対話入力を求められる。ネットワーク系パラメータ（`vpc_id` 等）はすべてデフォルト値なしのため、**`terraform.tfvars` の事前作成が必須**。

**推奨**: `terraform.tfvars.example` をコピーして `terraform.tfvars` を作成し、事前にすべての値を設定してから `terraform apply` を実行する。

```powershell
cp terraform.tfvars.example terraform.tfvars
# terraform.tfvars を編集してから実行
terraform apply
```

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

### コンテナ環境変数（IaCのスコープ外 / アプリ開発者が設定）

ECSコンテナに渡すアプリ固有の設定値（`DATABASE_URL` 等）は、IaCでは管理しません。  
アプリリポジトリの `taskdef.json` に直接記載します。

```json
"environment": [
  {"name": "APP_ENV",      "value": "production"},
  {"name": "DATABASE_URL", "value": "postgres://..."},
  {"name": "PORT",         "value": "80"}
]
```

| 設定場所 | 管理者 | 参照 |
|---|---|---|
| アプリリポジトリの `taskdef.json` | アプリ開発者 | [aws-cicd/docs/buildspec_design.md](../../aws-cicd/docs/buildspec_design.md) |

> **シークレット（パスワード・APIキー）は `taskdef.json` に直書きしないこと。**  
> AWS Secrets Manager / SSM Parameter Store を使い、`secrets` フィールドで参照することを推奨します。

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
    ├── root.yml                   ← ネストスタック頂点（全スタックを1コマンドでデプロイ）
    └── stacks/
        ├── 01-iam.yaml            ← ECS / CodeDeploy 用IAMロール
        ├── 02-alb.yaml            ← ALB + Target Group（Blue/Green）+ Listener
        ├── 03-ecs.yaml            ← ECS Cluster + Service + Task Definition
        └── 04-codedeploy.yaml     ← CodeDeploy Deployment Group
```

---

## 8. 前提条件

- AWS CLI v2 インストール済み・認証情報設定済み
- Terraform >= 1.6（Terraform版を使う場合）
- **tfstate 保存用 S3 バケットが作成済みであること**（Terraform版・初回のみ）。`terraform init` 実行前に AWS CLI で手動作成する
- VPC / Subnet / Security Group が構築済みであること
- `aws-cicd` のECRデプロイが完了していること（`ecr_repository_url` が必要）

---

## 9. 操作フロー

すべての構築操作はローカルPCから実行する。TerraformはローカルのCLIからAWS APIを経由してリソースを作成する。AWSコンソールはリソース確認の用途でのみ使用する。

| 操作の種類 | 操作場所 |
|---|---|
| terraform init / plan / apply | ローカルPC |
| 認証情報設定（aws configure） | ローカルPC |
| VPC / Subnet / Security Group の ID 確認 | AWSコンソール または ローカルPC（AWS CLI） |
| 構築結果の確認（ECS / ALB ステータス） | AWSコンソール |

### aws-app の構築フロー

```
[ローカルPC]                                         [AWS]
    │
    │ （事前に aws-cicd の terraform apply が完了していること）
    │       ecr_repository_url を取得済み ←────────  ECR（aws-cicdが管理）
    │
    ├─① aws-app: terraform apply ───────────────→  ECS / ALB / CodeDeploy 作成
    │                  ecs_cluster_name 等を取得 ←
    │
    ├─② aws-cicd: terraform apply（再実行）─────→  Deploy Stage 有効化
    │             ※ ecs_cluster_name 等を aws-cicd の tfvars に設定して実行
    │
    └─③ 動作確認
          curl http://<alb_dns_name>（ローカル操作）
          ECS / ALB ステータス確認（AWSコンソール）
```

---

## 10. 設計上の決定事項

| 決定 | 理由 |
|---|---|
| CI/CDとアプリ基盤を別リポジトリで管理する | パイプラインの再利用性・ライフサイクルの違い・既存ECS環境への適用を考慮 |
| CodeDeploy Deployment GroupはAWS-APP側に含める | ALB・ECSリソースへの参照が必要なため、アプリ基盤と一体で管理すべき |
| ALBを本リポジトリに含める | ECSへの入口かつBlue/Greenの切替装置であり、ECSと一体で管理すべき |
| CodeDeploy Application + Deployment GroupをAWS-APP側に含める | ECS・ALBリソースへの参照が必要なため、アプリ基盤と一体で管理すべき |
| CloudFormationはスタックを4本に分割 | IAM → ALB → ECS → CodeDeploy の順に依存関係があるため分割 |
