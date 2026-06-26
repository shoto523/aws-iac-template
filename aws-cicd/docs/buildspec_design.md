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
| `CONTAINER_NAME` | terraform.tfvars / CloudFormation パラメータ | コンテナ名（`taskdef.json` の `IMAGE1_NAME` に対応） |
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
| `taskdef.json` | **アプリ開発者が用意** | ECS タスク定義テンプレート（`<IMAGE1_NAME>` プレースホルダーを含む） |

> `imageDetail.json` の中身:
> ```json
> {"ImageURI": "123456789.dkr.ecr.ap-northeast-1.amazonaws.com/my-app:a1b2c3d4"}
> ```
> CodeDeploy がこのURIを `taskdef.json` の `<IMAGE1_NAME>` に埋め込んでデプロイする。

---

## 5. アプリ側で用意するファイル

アプリリポジトリのルートに以下3ファイルを配置してください。

### buildspec.yml

本リポジトリの `buildspec.yml` をそのままコピーして使用します。  
`CONTAINER_NAME` 等は CodePipeline から環境変数として渡されるため、原則編集不要です。

### appspec.yaml

CodeDeploy の動作定義です。コンテナ名とポートをアプリに合わせて変更してください。

```yaml
version: 0.0
Resources:
  - TargetService:
      Type: AWS::ECS::Service
      Properties:
        TaskDefinition: <TASK_DEFINITION>
        LoadBalancerInfo:
          ContainerName: "my-app"   # ← aws-cicd の CONTAINER_NAME に合わせる
          ContainerPort: 80         # ← アプリのポートに合わせる
```

### taskdef.json

ECS タスク定義のテンプレートです。`<IMAGE1_NAME>` は CodeDeploy が自動で実際のイメージ URI に置換します。

```json
{
  "family": "my-app",
  "networkMode": "awsvpc",
  "executionRoleArn": "arn:aws:iam::ACCOUNT_ID:role/my-app-ecs-task-execution-role",
  "containerDefinitions": [
    {
      "name": "<IMAGE1_NAME>",
      "image": "<IMAGE1_NAME>",
      "portMappings": [
        {
          "containerPort": 80,
          "protocol": "tcp"
        }
      ],
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "/ecs/my-app",
          "awslogs-region": "ap-northeast-1",
          "awslogs-stream-prefix": "ecs"
        }
      }
    }
  ],
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "256",
  "memory": "512"
}
```

> `executionRoleArn` は `aws-app` の出力値（ECS Task Execution Role ARN）を設定してください。

---

## 6. ファイル構成（アプリリポジトリ）

```
your-app-repo/
├── buildspec.yml     ← aws-cicd からコピー
├── appspec.yaml      ← アプリに合わせて作成
├── taskdef.json      ← アプリに合わせて作成
├── Dockerfile        ← アプリのDockerfile
└── src/              ← アプリのソースコード
```

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
