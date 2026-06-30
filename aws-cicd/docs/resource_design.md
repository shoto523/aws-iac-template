# リソース詳細設計書（aws-cicd）

Terraform の実装コードから起こしたリソース仕様。`${project_name}` はユーザーが `terraform.tfvars` で設定する値。

---

## ECR

### aws_ecr_repository

| 項目 | 値 |
|---|---|
| リソース名（AWS上） | `${project_name}` |
| イメージタグの変更可否 | MUTABLE（上書き可） |
| プッシュ時スキャン | 有効 |
| タグ | `Project: ${project_name}` |

### aws_ecr_lifecycle_policy

| 項目 | 値 |
|---|---|
| 保持するイメージ数 | 最新10件（タグの有無を問わず） |
| 削除対象 | 11件目以降を自動削除 |

---

## S3（アーティファクトバケット）

### aws_s3_bucket

| 項目 | 値 |
|---|---|
| バケット名 | `${project_name}-pipeline-artifacts-${AWSアカウントID}` |
| バージョニング | 有効（Enabled） |
| サーバーサイド暗号化 | AES256（SSE-S3） |
| パブリックアクセス | 全ブロック（4項目すべてtrue） |
| force_destroy | true（terraform destroy 時に中身ごと削除） |
| タグ | `Project: ${project_name}` |

> **現状の注記**: S3バケットは `modules/pipeline/main.tf` に定義されており、`module.iam` との循環依存が残っている。root `main.tf` への移動が予定されているが未実装。

---

## CloudWatch Logs

### aws_cloudwatch_log_group（CodeBuildビルドログ）

| 項目 | 値 |
|---|---|
| ロググループ名 | `/codebuild/${project_name}` |
| 保持期間 | 30日 |
| タグ | `Project: ${project_name}` |

---

## CodeBuild

### aws_codebuild_project

| 項目 | 値 |
|---|---|
| プロジェクト名 | `${project_name}-build` |
| コンピューティングタイプ | BUILD_GENERAL1_SMALL |
| ビルドイメージ | `aws/codebuild/standard:7.0` |
| 環境タイプ | LINUX_CONTAINER |
| 特権モード | true（Docker ビルドに必要） |
| buildspec | アプリリポジトリルートの `buildspec.yml` |
| ログ出力先 | `/codebuild/${project_name}`（ストリーム名: `build`） |
| タグ | `Project: ${project_name}` |

#### 環境変数

| 変数名 | 値 |
|---|---|
| `ECR_REPOSITORY_URI` | ECRリポジトリのURI |
| `AWS_DEFAULT_REGION` | デプロイ先リージョン |
| `CONTAINER_NAME` | `${project_name}` |

---

## CodePipeline

### aws_codepipeline

| 項目 | 値 |
|---|---|
| パイプライン名 | `${project_name}-pipeline` |
| アーティファクトストア | S3バケット（上記） |
| タグ | `Project: ${project_name}` |

#### ステージ構成

| ステージ | アクション | プロバイダー | 入力 | 出力 |
|---|---|---|---|---|
| Source（CodeCommit版） | Source | CodeCommit | — | `source_output` |
| Source（GitHub版） | Source | CodeStarSourceConnection | — | `source_output` |
| Build | Build | CodeBuild | `source_output` | `build_output` |
| Deploy | Deploy | CodeDeployToECS | `build_output` | — |

#### Source ステージ詳細（CodeCommit版）

| 項目 | 値 |
|---|---|
| リポジトリ名 | `${project_name}` |
| ブランチ | `${codecommit_branch}`（デフォルト: `main`） |
| アーティファクト形式 | CODE_ZIP |
| ポーリング | false（EventBridge で起動） |

#### Source ステージ詳細（GitHub版）

| 項目 | 値 |
|---|---|
| 接続ARN | CodeStar Connection ARN |
| リポジトリ | `${github_owner}/${github_repo}` |
| ブランチ | `${github_branch}`（デフォルト: `main`） |
| アーティファクト形式 | CODE_ZIP |

#### Deploy ステージ詳細

| 項目 | 値 |
|---|---|
| アプリケーション名 | `${codedeploy_app_name}`（aws-appの出力値） |
| デプロイグループ名 | `${codedeploy_group_name}`（aws-appの出力値） |
| タスク定義テンプレート | `build_output/taskdef.json` |
| AppSpecテンプレート | `build_output/appspec.yaml` |
| イメージ置換キー | `IMAGE1_NAME` |

---

## CodeCommit（CodeCommit版のみ）

### aws_codecommit_repository

| 項目 | 値 |
|---|---|
| リポジトリ名 | `${project_name}` |
| 説明 | `${project_name} source repository` |
| タグ | `Project: ${project_name}` |

---

## CodeStar Connections（GitHub版のみ）

### aws_codestarconnections_connection

| 項目 | 値 |
|---|---|
| 接続名 | `${project_name}-github` |
| プロバイダー種別 | GitHub |
| 初期ステータス | PENDING（デプロイ後にAWSコンソールで手動承認が必要） |
| タグ | `Project: ${project_name}` |

---

## IAM

### CodePipeline 実行ロール

| 項目 | 値 |
|---|---|
| ロール名 | `${project_name}-codepipeline-role` |
| 信頼するサービス | `codepipeline.amazonaws.com` |

#### アタッチされるポリシー

| ポリシー名 | 対象リソース | 許可アクション |
|---|---|---|
| `s3-artifact` | アーティファクトバケット | GetObject, GetObjectVersion, PutObject, GetBucketVersioning, ListBucket |
| `codebuild` | `${project_name}-build` | StartBuild, BatchGetBuilds |
| `codedeploy` | `*` | CreateDeployment, GetDeployment, RegisterApplicationRevision 他 + iam:PassRole |
| `codecommit`（CodeCommit版のみ） | CodeCommitリポジトリARN | GetBranch, GetCommit, GetRepository, GetUploadArchiveStatus, UploadArchive |
| `codestar-connections`（GitHub版のみ） | CodeStar Connection ARN | codestar-connections:UseConnection |

### CodeBuild 実行ロール

| 項目 | 値 |
|---|---|
| ロール名 | `${project_name}-codebuild-role` |
| 信頼するサービス | `codebuild.amazonaws.com` |

#### アタッチされるポリシー

| ポリシー名 | 対象リソース | 許可アクション |
|---|---|---|
| `ecr`（GetAuthorizationToken） | `*` | ecr:GetAuthorizationToken |
| `ecr`（イメージ操作） | ECRリポジトリARN | BatchCheckLayerAvailability, GetDownloadUrlForLayer, BatchGetImage, PutImage, InitiateLayerUpload, UploadLayerPart, CompleteLayerUpload |
| `s3-artifact` | アーティファクトバケット内オブジェクト | GetObject, GetObjectVersion, PutObject |
| `cloudwatch-logs` | `/codebuild/${project_name}*` | CreateLogGroup, CreateLogStream, PutLogEvents |

### EventBridge 実行ロール（CodeCommit版のみ）

| 項目 | 値 |
|---|---|
| ロール名 | `${project_name}-eventbridge-role` |
| 信頼するサービス | `events.amazonaws.com` |

#### アタッチされるポリシー

| ポリシー名 | 対象リソース | 許可アクション |
|---|---|---|
| `start-pipeline` | `${project_name}-pipeline` | codepipeline:StartPipelineExecution |

---

## EventBridge（CodeCommit版のみ）

### aws_cloudwatch_event_rule

| 項目 | 値 |
|---|---|
| ルール名 | `${project_name}-codecommit-push` |
| イベントソース | `aws.codecommit` |
| イベントタイプ | `CodeCommit Repository State Change` |
| 対象リソース | CodeCommitリポジトリARN |
| 検知条件 | `referenceCreated` または `referenceUpdated`（branch のみ） |
| 対象ブランチ | `${codecommit_branch}` |
| タグ | `Project: ${project_name}` |

### aws_cloudwatch_event_target

| 項目 | 値 |
|---|---|
| ターゲット | CodePipeline（`${project_name}-pipeline`） |
| 実行ロール | EventBridge 実行ロール |
