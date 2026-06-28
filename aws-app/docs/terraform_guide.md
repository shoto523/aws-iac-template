# Terraform 構築手順（aws-app）

## 1. 事前準備

### 必要なツールのインストール（ローカル操作）

| ツール | バージョン | インストール確認コマンド |
|---|---|---|
| AWS CLI | v2 以上 | `aws --version` |
| Terraform | >= 1.6 | `terraform -version` |

### 前提条件の確認

本リポジトリをデプロイする前に以下が揃っていること。

| 前提条件 | 確認場所 | 確認方法 |
|---|---|---|
| `aws-cicd` のデプロイ完了（ECR作成済み） | ローカル操作 | `terraform output ecr_repository_url`（aws-cicd/terraform/ で実行） |
| VPC / Subnet / Security Group が構築済み | AWSコンソール | EC2 → VPC / サブネット / セキュリティグループ で存在確認 |
| AWS CLI 認証情報設定済み | ローカル操作 | `aws sts get-caller-identity` |

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

---

## 2. terraform.tfvars の設定（ローカル操作）

`terraform/` ディレクトリに移動し、パラメータファイルを作成する。

```sh
cd terraform/
cp terraform.tfvars.example terraform.tfvars
```

`terraform.tfvars` を編集する。VPC・Subnet・Security Group の値は AWSコンソール（EC2 → VPC）または AWS CLI で確認する。

```hcl
project_name = "my-app"        # aws-cicd と同じプロジェクト名を使うと管理しやすい
aws_region   = "ap-northeast-1"

# ネットワーク情報（AWSコンソール または aws ec2 コマンドで確認した値を設定）
vpc_id                = "vpc-xxxxxxxx"
public_subnet_ids     = ["subnet-aaa", "subnet-bbb"]   # ALB 配置先（複数）
private_subnet_ids    = ["subnet-ccc", "subnet-ddd"]   # ECSタスク配置先（複数）
alb_security_group_id = "sg-xxxxxxxx"                  # ALB 用セキュリティグループ
ecs_security_group_id = "sg-yyyyyyyy"                  # ECSタスク用セキュリティグループ

# コンテナ情報
container_name   = "my-app"     # タスク定義のコンテナ名
container_port   = 80           # コンテナが公開するポート番号

# aws-cicd の出力値（ローカルで terraform output ecr_repository_url を実行して取得）
ecr_repository_url = "123456789012.dkr.ecr.ap-northeast-1.amazonaws.com/my-app"
```

VPC / Subnet / Security Group を CLI で確認する場合：

```sh
aws ec2 describe-vpcs --region ap-northeast-1 --query "Vpcs[*].{VpcId:VpcId,Name:Tags[?Key=='Name']|[0].Value}"
aws ec2 describe-subnets --region ap-northeast-1 --query "Subnets[*].{SubnetId:SubnetId,Name:Tags[?Key=='Name']|[0].Value,CidrBlock:CidrBlock}"
aws ec2 describe-security-groups --region ap-northeast-1 --query "SecurityGroups[*].{GroupId:GroupId,Name:GroupName}"
```

---

## 3. terraform init（ローカル操作）

```sh
terraform init \
  -backend-config="bucket=<YOUR_TFSTATE_BUCKET>" \
  -backend-config="key=aws-app/terraform.tfstate" \
  -backend-config="region=ap-northeast-1"
```

| オプション | 指定する値 | 例 |
|---|---|---|
| `bucket` | **バケット名のみ**（URLやARNではない） | `mycompany-tfstate-ap-northeast-1` |
| `key` | tfstateファイルのS3上のパス | `aws-app/terraform.tfstate` |
| `region` | バケットを作成したリージョン | `ap-northeast-1` |

> `aws-cicd` と同じ S3 バケットを使いまわせる。`key` を `aws-app/terraform.tfstate` とすることで別ファイルとして管理される。

成功すると以下のメッセージが表示される：

```
Terraform has been successfully initialized!
```

---

## 4. terraform plan（ローカル操作）

```sh
terraform plan
```

`Plan: X to add, 0 to change, 0 to destroy.` と表示されれば問題ない。  
特に以下のリソースが含まれていることを確認する：

- `aws_ecs_cluster`
- `aws_ecs_service`
- `aws_ecs_task_definition`
- `aws_lb`（ALB）
- `aws_lb_target_group`（Blue / Green の 2 つ）
- `aws_codedeploy_app`
- `aws_codedeploy_deployment_group`

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

ecs_cluster_name      = "my-app-cluster"
ecs_service_name      = "my-app-service"
codedeploy_app_name   = "my-app-deploy"
codedeploy_group_name = "my-app-deploy-group"
alb_dns_name          = "my-app-alb-xxxxxxxxx.ap-northeast-1.elb.amazonaws.com"
```

---

## 6. 出力値の確認（ローカル操作）

```sh
terraform output
```

以下の出力値を `aws-cicd` の `terraform.tfvars` に設定する。

| 出力名 | aws-cicd の tfvars キー |
|---|---|
| `ecs_cluster_name` | `ecs_cluster_name` |
| `ecs_service_name` | `ecs_service_name` |
| `codedeploy_app_name` | `codedeploy_app_name` |
| `codedeploy_group_name` | `codedeploy_group_name` |

---

## 7. aws-cicd の再デプロイ（ローカル操作）

`aws-app` の出力値を `aws-cicd/terraform/terraform.tfvars` に追記する。

```hcl
ecs_cluster_name      = "my-app-cluster"
ecs_service_name      = "my-app-service"
codedeploy_app_name   = "my-app-deploy"
codedeploy_group_name = "my-app-deploy-group"
```

`aws-cicd/terraform/` ディレクトリで再デプロイを実行する。

```sh
cd ../../aws-cicd/terraform/
terraform plan   # Deploy Stage の設定が更新されることを確認
terraform apply
```

これで Deploy Stage が有効になり、ソース push 時に ECR への push と ECS Blue/Green デプロイが自動で実行される。

---

## 8. 全体の構築順序（参考）

```
1. aws-cicd を terraform apply（初回）        ← ローカル操作
      ↓ ecr_repository_url を取得
2. aws-app を terraform apply（本ガイド）      ← ローカル操作
      ↓ ecs_cluster_name 等を取得
3. aws-cicd を terraform apply（再実行）       ← ローカル操作
      ↓ Deploy Stage が有効化
4. ソースリポジトリを接続                     ← ローカル / AWSコンソール（ソース種別による）
```

> aws-cicd 側の詳細手順は [aws-cicd/docs/terraform_guide.md](../../aws-cicd/docs/terraform_guide.md) を参照。

---

## 9. 動作確認

### アクセス確認（ローカル操作）

ALB の DNS 名にアクセスしてアプリケーションが応答することを確認する。

```sh
curl http://<alb_dns_name>
```

### リソース状態確認（AWSコンソール操作）

AWSコンソールで以下を確認する：

1. **ECS** → クラスター → `<project_name>-cluster` → サービス → タスクが `RUNNING` 状態になっていること
2. **EC2** → ターゲットグループ → `<project_name>-tg-blue` → ヘルスチェックが `healthy` になっていること

---

## 10. リソースの削除（ローカル操作）

```sh
terraform destroy
```

確認プロンプトに `yes` を入力するとすべてのリソースが削除される。

> ECS サービスが `ACTIVE` のままだと削除に失敗することがある。先に ECS サービスのタスク数を 0 にするか、`terraform destroy` のタイムアウトを延長すること。
