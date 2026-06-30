# Q&A

## Q1. 既存のECS環境とCI/CDを連携するにはどうすればいいか？

### 前提条件の確認

連携が成立するのは、**既存ECS側にCodeDeployが設定済みの場合のみ**です。

| 既存ECSの状態 | 連携可否 |
|---|---|
| CodeDeploy Application + Deployment Group が設定済み | ✅ パラメータを渡すだけで動く |
| ECSはあるがCodeDeployは未設定 | ❌ 先にCodeDeploy設定が必要（→ Q2参照） |

### 連携手順

**Step 1: 既存のCodeDeployリソース名を確認する**

```powershell
# CodeDeploy Application一覧
aws deploy list-applications --region ap-northeast-1

# Deployment Group一覧（アプリ名を指定）
aws deploy list-deployment-groups `
  --application-name <application-name> `
  --region ap-northeast-1
```

**Step 2: `terraform.tfvars` に既存リソース名を記載する（Terraform版）**

```hcl
ecs_cluster_name      = "既存のECSクラスター名"
ecs_service_name      = "既存のECSサービス名"
codedeploy_app_name   = "既存のCodeDeployアプリ名"
codedeploy_group_name = "既存のCodeDeployデプロイグループ名"
```

**Step 2: CloudFormationパラメータに渡す（CloudFormation版）**

```powershell
aws cloudformation deploy `
  --template-file root.yml `
  --stack-name <project_name>-cicd `
  --parameter-overrides `
    ProjectName=<project_name> `
    SourceType=codecommit `
    EcsClusterName=既存のECSクラスター名 `
    EcsServiceName=既存のECSサービス名 `
    CodeDeployAppName=既存のCodeDeployアプリ名 `
    CodeDeployGroupName=既存のCodeDeployデプロイグループ名 `
  --capabilities CAPABILITY_NAMED_IAM `
  --region ap-northeast-1
```

**Step 3: デプロイして動作確認**

パラメータを渡してデプロイ後、ソースリポジトリにpushしてパイプラインが正常に動作することを確認します。

---

## Q2. 既存ECSにCodeDeployが設定されていない場合はどうするか？

既存ECSにCodeDeployが未設定の場合、`aws-app` リポジトリの `04-codedeploy.yaml` のみデプロイすることで設定できます。

> ECS / ALB は既存のものを使い、CodeDeploy部分だけ `aws-app` で追加する形になります。

**Step 1: 既存リソースの情報を確認する**

```powershell
# ECSクラスター確認
aws ecs describe-clusters --region ap-northeast-1

# ECSサービス確認
aws ecs describe-services `
  --cluster <cluster-name> `
  --services <service-name> `
  --region ap-northeast-1

# ALB Target Group確認（Blue/Green用に2つ必要）
aws elbv2 describe-target-groups --region ap-northeast-1
```

**Step 2: ECSサービスのデプロイコントローラーを確認する**

既存ECSサービスのデプロイコントローラーが `CODE_DEPLOY` になっている必要があります。

```powershell
aws ecs describe-services `
  --cluster <cluster-name> `
  --services <service-name> `
  --region ap-northeast-1 `
  --query "services[0].deploymentController"
```

出力が `{"type": "CODE_DEPLOY"}` であれば問題ありません。  
`ECS`（ローリングアップデート）の場合は、サービスの再作成が必要です。

**Step 3: `aws-app` の `04-codedeploy.yaml` のみデプロイする**

```powershell
cd aws-app/cloudformation
aws cloudformation deploy `
  --stack-name <project-name>-codedeploy `
  --template-file stacks/04-codedeploy.yaml `
  --parameter-overrides `
    EcsClusterName=<既存クラスター名> `
    EcsServiceName=<既存サービス名> `
    TargetGroupBlueArn=<Blue Target GroupのARN> `
    TargetGroupGreenArn=<Green Target GroupのARN> `
    ProdListenerArn=<本番リスナー(:80)のARN> `
    TestListenerArn=<テストリスナー(:8080)のARN> `
  --capabilities CAPABILITY_NAMED_IAM `
  --region ap-northeast-1
```

**Step 4: 出力値を確認して Q1 の手順に進む**

```powershell
aws cloudformation describe-stacks `
  --stack-name <project-name>-codedeploy `
  --region ap-northeast-1 `
  --query "Stacks[0].Outputs"
```

出力された `codedeploy_app_name` と `codedeploy_group_name` を Q1 の手順で `aws-cicd` のパラメータに渡します。

---

## Q3. Deploy Stageだけ失敗する場合の確認ポイント

| 確認項目 | 確認方法 |
|---|---|
| CodeDeploy Deployment Groupが存在するか | `aws deploy get-deployment-group --application-name <app> --deployment-group-name <group>` |
| ECSサービスのデプロイコントローラーが `CODE_DEPLOY` か | Q2のStep 2参照 |
| ALBにBlue/Green用Target Groupが2つあるか | AWSコンソール → EC2 → ターゲットグループ |
| IAMロールにCodeDeploy実行権限があるか | AWSコンソール → IAM → ロール |

---

## Q4. CodeStar Connections とは何か？

AWS CodePipeline と GitHub（または Bitbucket / GitLab）を接続するための **認証機構サービス**です。

CodePipeline は AWS 内のサービスであり、そのままでは GitHub のプライベートリポジトリにアクセスできません。CodeStar Connections を使うことで、AWS と GitHub の間に安全な接続を確立し、push イベントの検知やソースコードの取得が可能になります。

| 項目 | 内容 |
|---|---|
| 役割 | AWS サービス（CodePipeline）と外部 Git リポジトリ（GitHub 等）を繋ぐ認証ブリッジ |
| 接続ステータス | 作成直後は `PENDING`。手動承認後に `AVAILABLE` になる |
| 手動承認が必要な理由 | GitHub 側でAWSからのアクセスを許可する操作が必要なため、IaC だけでは完結しない |
| 承認手順 | [docs/setup_guide_github.md](setup_guide_github.md#step-2-github-との接続を手動承認する) |

> `AVAILABLE` にならないと CodePipeline は起動しません。デプロイ後は必ずステータスを確認してください。

---

## Q5. 設計書に記載の `>=`（バージョン要件表記）とはどういう意味か？

`>=` は「**以上**」を意味する比較演算子です。ソフトウェアの依存関係を表記する際に広く使われます。

| 表記 | 意味 |
|---|---|
| `Terraform >= 1.6` | Terraform のバージョン 1.6 以上が必要 |
| `>=` | greater than or equal to（以上） |
| `>` | greater than（より大きい） |
| `<=` | less than or equal to（以下） |

インストール済みのバージョンは `terraform version` コマンドで確認できます。

---

## Q6. buildspec.yml で ECR ログインが必要な理由は？

ECR はプライベートな Docker レジストリのため、`docker push` の前に認証が必要です。

```bash
aws ecr get-login-password --region ap-northeast-1 \
  | docker login --username AWS --password-stdin <ECR_URI>
```

| ステップ | 処理 |
|---|---|
| `aws ecr get-login-password` | CodeBuild の IAM ロール権限で一時トークンを取得（有効期限12時間） |
| `docker login` | そのトークンを使って Docker デーモンを ECR に認証 |
| `docker push` | 認証済み状態で ECR にイメージを送信 |

ログインを省くと `no basic auth credentials` エラーで `docker push` が失敗します。

---

## Q7. appspec.yaml と taskdef.json が必要な理由は？

CodeDeploy の ECS Blue/Green デプロイには以下の3ファイルが必要です。  
`taskdef.json` は `buildspec.yml` が自動生成するため、アプリ開発者が用意するのは `appspec.yaml` のみです。

| ファイル | 作成者 | 役割 |
|---|---|---|
| `imageDetail.json` | buildspec.yml が自動生成 | ECR にプッシュしたイメージの URI を記録 |
| `taskdef.json` | buildspec.yml が自動生成 | ECS タスク定義のテンプレート（`TASK_EXECUTION_ROLE_ARN` 等は Terraform から注入） |
| `appspec.yaml` | アプリ開発者が用意 | どの ECS サービスにデプロイするかを CodeDeploy に伝える |

**動作の流れ:**

```
imageDetail.json の ImageURI
        ↓
taskdef.json の <IMAGE1_NAME> を実際の URI に置換
        ↓
新しい ECS タスク定義を登録
        ↓
appspec.yaml に従って ECS サービスを Blue/Green で切り替え
```

どれか1つ欠けても Deploy Stage が失敗します。各ファイルのテンプレートは [docs/buildspec_design.md](buildspec_design.md) を参照してください。

---

## Q8. buildspec.yml はアプリをコミットするたびに入れる必要があるか？

いいえ。最初に1回だけコミットしてリポジトリに置いておくものです。

```
your-app-repo/
├── buildspec.yml   ← 最初に1回置く。以後ほぼ変更なし
├── appspec.yaml    ← 同上
├── Dockerfile      ← 同上
└── src/            ← ここを毎回コミット・push する
```

> `taskdef.json` はビルド時に `buildspec.yml` が自動生成するため、アプリリポジトリに置く必要はありません。

`aws-cicd/buildspec.yml` と `aws-cicd/appspec.yaml` にサンプルを用意しています。アプリリポジトリ作成時にコピーして使用してください。

---

## Q9. terraform apply で「Map value must satisfy constraint: length >= 1」エラーが出る

Deploy Stage の設定値（`codedeploy_app_name` / `codedeploy_group_name`）が空文字のまま apply したときに発生する。AWS CodePipeline は設定値に空文字を許可しない。

**原因**: aws-app をデプロイする前に aws-cicd を apply した。

**解決策**: `terraform.tfvars` の `codedeploy_app_name` と `codedeploy_group_name` が空文字のままでも apply できるよう、Deploy Stage は条件付きになっている（値が設定されていないときは Source + Build の2ステージで動作する）。

つまり:
- **初回 apply（aws-app デプロイ前）**: Source + Build の2ステージで作成される → エラーは出ない
- **aws-app デプロイ後に再 apply**: Deploy Stage が追加される → 3ステージになり完成

このエラーが出た場合は `terraform.tfvars` を確認し、値が正しく設定されているかを確認する。
