# Terraform 構築手順（aws-cicd）

## 1. 事前準備

### 必要なツールのインストール（ローカル操作）

| ツール | バージョン | インストール確認コマンド |
|---|---|---|
| AWS CLI | v2 以上 | `aws --version` |
| Terraform | >= 1.6 | `terraform -version` |

### AWS 認証情報の設定（ローカル操作）

取得済みのIAMアクセスキーをAWS CLIに設定する。

```sh
aws configure
# AWS Access Key ID: <アクセスキー>
# AWS Secret Access Key: <シークレットキー>
# Default region name: ap-northeast-1
# Default output format: json
```

設定確認：

```sh
aws sts get-caller-identity
```

アカウントIDとユーザー情報が表示されれば正常。

> アクセスキーの発行方法は [setup_guide.md Step 1](setup_guide.md) を参照。

### tfstate 保存用 S3 バケットの作成（ローカル操作 / 初回のみ）

Terraform のステートファイルを S3 で管理するため、事前にバケットを作成する。

```sh
# S3バケットを作成する
# --bucket                      : バケット名（グローバルで一意な名前をつける。例: mycompany-tfstate-ap-northeast-1）
# --region                      : バケットを作成するリージョン
# --create-bucket-configuration : us-east-1 以外のリージョンで作成する際に必須のオプション
aws s3api create-bucket \
  --bucket <YOUR_TFSTATE_BUCKET> \
  --region ap-northeast-1 \
  --create-bucket-configuration LocationConstraint=ap-northeast-1

# バージョニングを有効化する
# tfstate が更新されるたびに以前のバージョンが保持されるため、
# 誤って terraform apply した場合などにロールバックが可能になる
# Status=Enabled : バージョニングをオンにする
aws s3api put-bucket-versioning \
  --bucket <YOUR_TFSTATE_BUCKET> \
  --versioning-configuration Status=Enabled
```

---

## 2. terraform.tfvars の設定（ローカル操作）

`terraform/` ディレクトリに移動し、パラメータファイルを作成する。

```sh
cd terraform/
cp terraform.tfvars.example terraform.tfvars
```

`terraform.tfvars` を編集する。

```hcl
project_name = "my-app"        # リソース名プレフィックス（他と重複しない名前）
aws_region   = "ap-northeast-1"

# ソース種別: "codecommit" または "github" のどちらか一方を選択
source_type = "codecommit"

# ---- CodeCommit版のみ設定（GitHub版を使う場合はこのブロックを削除してよい） ----
codecommit_branch = "main"

# ---- GitHub版のみ設定（CodeCommit版を使う場合はこのブロックを削除してよい） ----
# source_type    = "github"
# github_owner   = "your-github-username"
# github_repo    = "your-repo-name"
# github_branch  = "main"

# ---- aws-app デプロイ後に設定（初回は空文字のままでよい）----
ecs_cluster_name      = ""
ecs_service_name      = ""
codedeploy_app_name   = ""
codedeploy_group_name = ""
```

使用しない方のソースブロックは **削除して構わない**。`variables.tf` で各変数に `default = ""` が設定されているため、記載がなくてもエラーにならない。

> **注意**: `terraform.tfvars` は認証情報やシークレットを含む場合があるため `.gitignore` に追加すること。

---

## 3. terraform init（ローカル操作）

バックエンド（S3）の設定を渡しながら初期化する。

```sh
terraform init \
  -backend-config="bucket=<YOUR_TFSTATE_BUCKET>" \
  -backend-config="key=aws-cicd/terraform.tfstate" \
  -backend-config="region=ap-northeast-1"
```

| オプション | 指定する値 | 例 |
|---|---|---|
| `bucket` | **バケット名のみ**（URLやARNではない） | `mycompany-tfstate-ap-northeast-1` |
| `key` | tfstateファイルのS3上のパス | `aws-cicd/terraform.tfstate` |
| `region` | バケットを作成したリージョン | `ap-northeast-1` |

成功すると以下のメッセージが表示される：

```
Terraform has been successfully initialized!
```

> バケット名を `backend.tf` に直接書いてもよい。その場合は `terraform init` のみで初期化できる。

---

## 4. terraform plan（ローカル操作）

実際にリソースを作成する前に差分を確認する。

```sh
terraform plan
```

`Plan: X to add, 0 to change, 0 to destroy.` と表示されれば問題ない。

---

## 5. terraform apply（ローカル操作）

```sh
terraform apply
```

確認プロンプトが表示されたら `yes` を入力する。

```
Do you want to perform these actions?
  ...
Enter a value: yes
```

完了すると以下のような出力が表示される：

```
Apply complete! Resources: X added, 0 changed, 0 destroyed.

Outputs:

ecr_repository_url   = "123456789012.dkr.ecr.ap-northeast-1.amazonaws.com/my-app"
pipeline_name        = "my-app-pipeline"
artifact_bucket_name = "my-app-artifact-xxxxxxxx"
```

---

## 6. 出力値の確認（ローカル操作）

`ecr_repository_url` を `aws-app` のデプロイ時に使用するため、メモしておく。

```sh
terraform output ecr_repository_url
```

---

## 7. ソースリポジトリの接続セットアップ

Terraform デプロイ完了後、ソースリポジトリを接続する。ソース種別によって操作場所が異なる。

| ソース種別 | 操作場所 | 手順 |
|---|---|---|
| CodeCommit | ローカル操作 | [setup_guide.md](setup_guide.md) を参照 |
| GitHub | AWSコンソール操作（手動承認）+ ローカル操作 | [setup_guide_github.md](setup_guide_github.md) を参照 |

---

## 8. アプリリポジトリへのファイル配置（ローカル操作）

パイプラインが正常に動作するために、以下の2ファイルをアプリリポジトリのルートに配置する。  
`taskdef.json` は `buildspec.yml` がビルド時に自動生成するため、配置不要。

| ファイル | 配置元 | 説明 |
|---|---|---|
| `buildspec.yml` | `aws-cicd/buildspec.yml` をコピー | CodeBuild のビルド定義。環境変数は CodePipeline から自動注入されるため編集不要 |
| `appspec.yaml` | `aws-cicd/appspec.yaml` をコピー | CodeDeploy の動作定義。そのまま使用可 |

アプリリポジトリのルート構成例：

```
your-app-repo/
├── buildspec.yml     ← aws-cicd/buildspec.yml をコピー（編集不要）
├── appspec.yaml      ← aws-cicd/appspec.yaml をコピー（編集不要）
├── Dockerfile        ← アプリの Dockerfile
└── src/              ← アプリのソースコード
```

> `taskdef.json` は `buildspec.yml` の post_build フェーズで CodeBuild が自動生成する。  
> 生成に必要な `TASK_EXECUTION_ROLE_ARN` 等は Terraform から環境変数として自動注入される。  
> 詳細は [buildspec_design.md](buildspec_design.md) を参照。

---

## 9. aws-app のデプロイ（ローカル操作 / 新規ECS構築時のみ）

ECS・ALB・CodeDeploy を構築する。

> **前提**: VPC・Subnet・Security Group はこのテンプレートの管理対象外です。事前に作成済みのものを使用します。

`aws-app` リポジトリに移動して以下を実行する。

```sh
cd ../../aws-app/terraform/
cp terraform.tfvars.example terraform.tfvars
```

`terraform.tfvars` を編集し、VPC・Subnet・Security Group の値と Step 6 で取得した `ecr_repository_url` を設定する。

```hcl
project_name       = "my-app"
aws_region         = "ap-northeast-1"
vpc_id             = "vpc-xxxxxxxx"
public_subnet_ids  = ["subnet-aaa", "subnet-bbb"]  # ALB・ECSタスク共通（異なるAZに2つ以上）
alb_security_group_id = "sg-xxxxxxxx"
ecs_security_group_id = "sg-yyyyyyyy"
container_name     = "my-app"
container_port     = 80
ecr_repository_url = "<Step 6 で取得した ecr_repository_url>"
```

> 各パラメータの詳細は [aws-app/docs/terraform_guide.md](../../aws-app/docs/terraform_guide.md) を参照。

```sh
terraform init \
  -backend-config="bucket=<YOUR_TFSTATE_BUCKET>" \
  -backend-config="key=aws-app/terraform.tfstate" \
  -backend-config="region=ap-northeast-1"

terraform plan
terraform apply
```

完了後、次の Step で使用する出力値を確認する。

```sh
terraform output
```

```
ecs_cluster_name        = "my-app-cluster"
ecs_service_name        = "my-app-service"
codedeploy_app_name     = "my-app-deploy"
codedeploy_group_name   = "my-app-deploy-group"
task_execution_role_arn = "arn:aws:iam::123456789012:role/my-app-ecs-task-execution-role"
```

---

## 10. aws-app デプロイ後の再設定（ローカル操作 / 新規ECS構築時のみ）

Step 8 の出力値を `aws-cicd/terraform/terraform.tfvars` に追記して再デプロイする。

```sh
cd ../../aws-cicd/terraform/
```

```hcl
ecs_cluster_name        = "my-app-cluster"                                              # aws-app の出力値
ecs_service_name        = "my-app-service"                                               # aws-app の出力値
codedeploy_app_name     = "my-app-deploy"                                                # aws-app の出力値
codedeploy_group_name   = "my-app-deploy-group"                                          # aws-app の出力値
task_execution_role_arn = "arn:aws:iam::123456789012:role/my-app-ecs-task-execution-role" # aws-app の出力値
```

```sh
terraform plan   # 差分確認（Deploy Stage の設定が更新される）
terraform apply
```

これで Deploy Stage が有効になり、ソース push → ビルド → ECS デプロイの一連のパイプラインが動作する。

---

## 11. 全体の構築順序（新規ECS構築の場合）

```
1. aws-cicd を terraform apply（初回）               ← ローカル操作
      ↓ ecr_repository_url を取得
2. ソースリポジトリを接続                            ← ローカル / AWSコンソール（ソース種別による）
3. アプリリポジトリに buildspec.yml / appspec.yaml / taskdef.json を配置
      ↓ taskdef.json のプレースホルダーを書き換え
4. aws-app を terraform apply                        ← ローカル操作
      ↓ ecs_cluster_name 等を取得
5. aws-cicd を terraform apply（再実行）             ← ローカル操作
      ↓ Deploy Stage が有効化
```

> **既存ECS連携の場合:** aws-app は不要。既存リソース名を最初から tfvars に設定してデプロイする（[詳細 → qa.md](qa.md)）。

---

## 12. リソースの削除（ローカル操作）

```sh
terraform destroy
```

確認プロンプトに `yes` を入力するとすべてのリソースが削除される。

> ECR にイメージが存在する場合、削除に失敗することがある。先に ECR リポジトリ内のイメージを削除してから実行すること。

```sh
# ECR イメージを先に削除する場合
aws ecr list-images --repository-name <REPO_NAME> --query 'imageIds' --output json \
  | xargs -I{} aws ecr batch-delete-image --repository-name <REPO_NAME> --image-ids {}
```
