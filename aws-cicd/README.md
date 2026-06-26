# aws-cicd-ecs

![Terraform](https://img.shields.io/badge/Terraform-844FBA?style=for-the-badge&logo=terraform&logoColor=white)
![CloudFormation](https://img.shields.io/badge/CloudFormation-FF9900?style=for-the-badge&logo=amazonaws&logoColor=white)
![AWS](https://img.shields.io/badge/AWS-232F3E?style=for-the-badge&logo=amazonwebservices&logoColor=white)
![CodePipeline](https://img.shields.io/badge/CodePipeline-232F3E?style=for-the-badge&logo=amazonaws&logoColor=white)
![License](https://img.shields.io/badge/License-MIT-green?style=for-the-badge)

**AWS上にCI/CDパイプラインを即時構築するIaCコード集。**  
Terraform版とCloudFormation版の両方を提供します。

---

## Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│  CI/CD Pipeline（本リポジトリのスコープ）                        │
│                                                                  │
│  [CodeCommit]                                                    │
│     │ push をトリガー（EventBridge経由）                          │
│     ▼                                                            │
│  [CodePipeline]                                                  │
│     ├─ Source Stage  : CodeCommitからソース取得 → S3へ格納       │
│     ├─ Build Stage   : CodeBuild                                 │
│     │    ├─ テスト実行                                           │
│     │    ├─ Docker ビルド                                        │
│     │    └─ ECR へ push                                          │
│     └─ Deploy Stage  : CodeDeploy（ECSは別途アプリ側で管理）     │
│                                                                  │
│  [ECR]  ← CodeBuild が push する                                 │
│  [S3]   ← アーティファクト保管                                   │
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

### Step 3: CodeCommit に接続してコードを push する

[docs/setup_guide.md](docs/setup_guide.md) の手順に従い、ローカルと CodeCommit を接続します。  
接続後、アプリケーションのコードを push すると CodePipeline が自動起動します。

---

## Directory Structure

```
aws-cicd-ecs/
├── README.md
├── buildspec.yml                  # CodeBuildビルド定義サンプル（アプリリポジトリに配置して使用）
├── docs/
│   ├── design.md                  # 設計書（スコープ・インターフェース定義）
│   ├── setup_guide.md             # CodeCommit版 接続セットアップ手順
│   └── setup_guide_github.md      # GitHub版 接続セットアップ手順
├── terraform/                     # Terraform 版 IaC（作成中）
│   └── modules/
│       ├── ecr/                   # ECR リポジトリ（共通）
│       ├── source-codecommit/     # CodeCommit + EventBridge（CodeCommit版）
│       ├── source-github/         # CodeStar Connections（GitHub版）
│       └── pipeline/              # CodePipeline + CodeBuild + S3 + IAM（共通）
└── cloudformation/                # CloudFormation 版 IaC（作成中）
    └── stacks/
        ├── 01-ecr.yaml                # ECR リポジトリ（共通）
        ├── 02-source-codecommit.yaml  # CodeCommit版 ← どちらか一方を選択
        ├── 02-source-github.yaml      # GitHub版    ←
        └── 03-pipeline.yaml           # CodePipeline + CodeBuild + S3 + IAM（共通）
```

---

## AWS Resources

| リソース | 説明 |
|---|---|
| CodeCommit | ソースコードリポジトリ |
| EventBridge | CodeCommitのpushイベントを検知してCodePipelineを起動 |
| CodePipeline | CI/CDパイプラインのオーケストレーション |
| CodeBuild | Dockerビルド・テスト実行 |
| CodeDeploy | デプロイ設定（ECSはアプリ側で管理） |
| ECR | Dockerイメージリポジトリ。将来のECS構築を見越して構築している。ECSを構築しない場合でも、ECRのみ存在する状態で問題ない |
| S3 | CodePipelineアーティファクトバケット |
| CloudWatch Logs | ビルドログ |
| IAM | 各サービス用最小権限ロール |

---

## License

MIT License
