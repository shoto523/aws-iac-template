# Terraform 構築手順（aws-cicd）

## 1. 事前準備

### 必要なツール

| ツール | バージョン | インストール確認コマンド |
|---|---|---|
| AWS CLI | v2 以上 | `aws --version` |
| Terraform | >= 1.6 | `terraform -version` |

### AWS 認証情報の設定

```sh
aws configure
# AWS Access Key ID: <アクセスキー>
# AWS Secret Access Key: <シークレットキー>
# Default region name: ap-northeast-1
# Default output format: json
```

または環境変数で設定する場合：

```sh
export AWS_ACCESS_KEY_ID="<アクセスキー>"
export AWS_SECRET_ACCESS_KEY="<シークレットキー>"
export AWS_DEFAULT_REGION="ap-northeast-1"
```

### tfstate 保存用 S3 バケットの作成（初回のみ）

Terraform のステートファイルを S3 で管理するため、事前にバケットを作成する。

```sh
aws s3api create-bucket \
  --bucket <YOUR_TFSTATE_BUCKET> \
  --region ap-northeast-1 \
  --create-bucket-configuration LocationConstraint=ap-northeast-1

# バージョニング有効化（推奨）
aws s3api put-bucket-versioning \
  --bucket <YOUR_TFSTATE_BUCKET> \
  --versioning-configuration Status=Enabled
```

---

## 2. terraform.tfvars の設定

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

# ---- CodeCommit版のみ設定 ----
codecommit_branch = "main"

# ---- GitHub版のみ設定 ----
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

> **注意**: `terraform.tfvars` は認証情報やシークレットを含む場合があるため `.gitignore` に追加すること。

---

## 3. terraform init

バックエンド（S3）の設定を渡しながら初期化する。

```sh
terraform init \
  -backend-config="bucket=<YOUR_TFSTATE_BUCKET>" \
  -backend-config="key=aws-cicd/terraform.tfstate" \
  -backend-config="region=ap-northeast-1"
```

成功すると以下のメッセージが表示される：

```
Terraform has been successfully initialized!
```

> バケット名を `backend.tf` に直接書いてもよい。その場合は `terraform init` のみで初期化できる。

---

## 4. terraform plan（変更内容の確認）

実際にリソースを作成する前に差分を確認する。

```sh
terraform plan
```

`Plan: X to add, 0 to change, 0 to destroy.` と表示されれば問題ない。

---

## 5. terraform apply（リソース作成）

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

## 6. 出力値の確認

`ecr_repository_url` を `aws-app` のデプロイ時に使用するため、メモしておく。

```sh
terraform output ecr_repository_url
```

---

## 7. ソースリポジトリの接続セットアップ

Terraform デプロイ完了後、ソースリポジトリを接続する。

| ソース種別 | 手順 |
|---|---|
| CodeCommit | [setup_guide.md](setup_guide.md) を参照 |
| GitHub | [setup_guide_github.md](setup_guide_github.md) を参照 |

---

## 8. aws-app デプロイ後の再設定（新規ECS構築時のみ）

`aws-app` のデプロイが完了したら、その出力値を `terraform.tfvars` に追記して再デプロイする。

```hcl
ecs_cluster_name      = "my-app-cluster"      # aws-app の出力値
ecs_service_name      = "my-app-service"       # aws-app の出力値
codedeploy_app_name   = "my-app-deploy"        # aws-app の出力値
codedeploy_group_name = "my-app-deploy-group"  # aws-app の出力値
```

```sh
terraform plan   # 差分確認（Deploy Stage の設定が更新される）
terraform apply
```

これで Deploy Stage が有効になり、ソース push → ビルド → ECS デプロイの一連のパイプラインが動作する。

---

## 9. 全体の構築順序（新規ECS構築の場合）

```
1. aws-cicd を terraform apply（初回）
      ↓ ecr_repository_url を取得
2. aws-app を terraform apply
      ↓ ecs_cluster_name / ecs_service_name / codedeploy_app_name / codedeploy_group_name を取得
3. aws-cicd を terraform apply（再実行 / aws-app の出力値をセット）
      ↓ Deploy Stage が有効化
4. ソースリポジトリを接続（setup_guide.md / setup_guide_github.md）
```

> **既存ECS連携の場合:** aws-app は不要。既存リソース名を最初から tfvars に設定してデプロイする（[詳細 → qa.md](qa.md)）。

---

## 10. リソースの削除

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
