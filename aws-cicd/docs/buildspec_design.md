# buildspec.yml 設計書

## 1. 概要

`buildspec.yml` は AWS CodeBuild のビルド定義ファイルです。  
**アプリリポジトリのルートに配置して使用します。**

> **サンプルファイルについて**: `aws-cicd/buildspec.yml` としてサンプルを作成済みです。  
> アプリリポジトリを作成する際にそのままコピーして使用してください。内容はアプリの要件に合わせて変更可能です。

CodePipeline の Build Stage で CodeBuild が起動すると、アプリリポジトリのルートにある `buildspec.yml` を読み込み、以下を自動実行します。

1. ECR へのログイン
2. Docker イメージのビルド
3. ECR への push
4. CodeDeploy ECS Blue/Green に必要なファイルの生成

---

## 2. 環境変数

CodePipeline → CodeBuild へ自動注入される変数です。アプリ側で設定は不要です。

| 変数名 | 値の出所 | 説明 |
|---|---|---|
| `ECR_REPOSITORY_URI` | aws-cicd の出力値 `ecr_repository_url` | ECR リポジトリの URI |
| `AWS_DEFAULT_REGION` | terraform.tfvars / CloudFormation パラメータ | デプロイ先リージョン |
| `CONTAINER_NAME` | terraform.tfvars / CloudFormation パラメータ | コンテナ名・プロジェクト名（`taskdef.json` の `family` / `name` に使用） |
| `TASK_EXECUTION_ROLE_ARN` | aws-app の出力値 `task_execution_role_arn` | ECS Task Execution ロールのARN（`taskdef.json` の `executionRoleArn` に使用） |
| `CODEBUILD_RESOLVED_SOURCE_VERSION` | CodeBuild が自動設定 | ソースコードのコミットハッシュ（イメージタグに使用） |

---

## 3. ビルドフェーズ

```yaml
phases:
  pre_build:   # ECR ログイン、イメージタグ（コミットハッシュ先頭8文字）を生成
  build:       # docker build → docker tag
  post_build:  # docker push → imageDetail.json 生成
```

| フェーズ | 処理内容 |
|---|---|
| pre_build | ECR へ `aws ecr get-login-password` でログイン。イメージタグとしてコミットハッシュ先頭8文字を取得 |
| build | `docker build` でイメージをビルド。`latest` タグも付与 |
| post_build | `docker push` で ECR へ push。`imageDetail.json` を生成 |

---

## 4. 出力アーティファクト

Build Stage の出力（`build_output`）として Deploy Stage に渡されるファイル群です。

| ファイル | 作成者 | 説明 |
|---|---|---|
| `imageDetail.json` | buildspec.yml が自動生成 | ECR にプッシュしたイメージの URI を記録。CodeDeploy が参照する |
| `appspec.yaml` | **アプリ開発者が用意** | CodeDeploy の動作定義（デプロイ先コンテナ名・ポートを指定） |
| `taskdef.json` | **buildspec.yml が自動生成** | ECS タスク定義テンプレート（`TASK_EXECUTION_ROLE_ARN` 等は Terraform から注入） |

> `imageDetail.json` の中身:
> ```json
> {"ImageURI": "123456789.dkr.ecr.ap-northeast-1.amazonaws.com/my-app:a1b2c3d4"}
> ```
> CodeDeploy がこのURIを `taskdef.json` の `<IMAGE1_NAME>` に埋め込んでデプロイする。

---

## 5. アプリ側で用意するファイル

アプリリポジトリのルートに以下の **2ファイル** を配置してください。  
`taskdef.json` は `buildspec.yml` がビルド時に自動生成するため、アプリ側での用意は不要です。

### buildspec.yml

本リポジトリの `aws-cicd/buildspec.yml` をそのままコピーして使用します。  
`CONTAINER_NAME` / `TASK_EXECUTION_ROLE_ARN` 等は CodePipeline から環境変数として渡されるため、編集不要です。

### appspec.yaml

本リポジトリの `aws-cicd/appspec.yaml` をそのままコピーして使用します。  
`ContainerName` は Terraform の `project_name` と一致しているため、編集不要です。

```yaml
version: 0.0
Resources:
  - TargetService:
      Type: AWS::ECS::Service
      Properties:
        TaskDefinition: <TASK_DEFINITION>
        LoadBalancerInfo:
          ContainerName: "my-app"   # project_name と一致
          ContainerPort: 80
```

### taskdef.json（自動生成）

`buildspec.yml` の post_build フェーズで自動生成されます。アプリ側での用意は不要です。

| フィールド | 値の出所 |
|---|---|
| `family` / `name` | `CONTAINER_NAME`（= `project_name`）環境変数 |
| `executionRoleArn` | `TASK_EXECUTION_ROLE_ARN`（= aws-app の出力値）環境変数 |
| `awslogs-region` | `AWS_DEFAULT_REGION` 環境変数 |
| `image` | `<IMAGE1_NAME>`（CodeDeploy が `imageDetail.json` の URI で自動置換） |

> **コンテナ環境変数（`DATABASE_URL` 等）を追加したい場合** は、`buildspec.yml` の taskdef.json 生成コマンド内の `containerDefinitions` に `environment` フィールドを追記してください。  
> **シークレットは直書きせず** AWS Secrets Manager / SSM Parameter Store を使用することを推奨します。

---

## 6. ファイル構成（アプリリポジトリ）

```
your-app-repo/
├── buildspec.yml     ← aws-cicd からコピー（編集不要）
├── appspec.yaml      ← aws-cicd からコピー（編集不要）
├── Dockerfile        ← アプリの Dockerfile
└── src/              ← アプリのソースコード
```

> `taskdef.json` はビルド時に自動生成されるため、アプリリポジトリには不要です。

---

## 7. Deploy Stage との連携

```
Build Stage（CodeBuild）
  └─ build_output アーティファクト（imageDetail.json + appspec.yaml + taskdef.json）
          ↓
Deploy Stage（CodeDeployToECS）
  ├─ imageDetail.json → イメージ URI を取得
  ├─ taskdef.json の <IMAGE1_NAME> を imageDetail.json の URI で置換
  ├─ 新しいタスク定義を ECS に登録
  └─ CodeDeploy が Blue/Green デプロイを実行
```
