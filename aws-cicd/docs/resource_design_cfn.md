# リソース詳細設計書 - CloudFormation版（aws-cicd）

CloudFormation スタックは未実装のため、Terraform 実装と design.md を元にした設計仕様。  
実装時にはこの仕様に従ってスタックを作成し、完了後に実コードと照合して更新する。

`${ProjectName}` は `root.yml` の `Parameters` セクションからすべての子スタックに渡される値。

---

## root.yml（ネストスタック頂点）

すべての子スタックをこのファイルから展開する。1コマンドでデプロイ完了。

### Parameters（入力パラメータ）

| パラメータ名 | 型 | デフォルト | 説明 |
|---|---|---|---|
| `ProjectName` | String | — | リソース名プレフィックス |
| `SourceType` | String | `codecommit` | `codecommit` または `github` |
| `CodeCommitBranch` | String | `main` | トリガー対象ブランチ（CodeCommit版） |
| `GitHubOwner` | String | `""` | GitHubオーナー名（GitHub版） |
| `GitHubRepo` | String | `""` | GitHubリポジトリ名（GitHub版） |
| `GitHubBranch` | String | `main` | トリガー対象ブランチ（GitHub版） |
| `EcsClusterName` | String | `""` | デプロイ先ECSクラスター名（aws-appの出力値） |
| `EcsServiceName` | String | `""` | デプロイ先ECSサービス名（aws-appの出力値） |
| `CodeDeployAppName` | String | `""` | CodeDeployアプリ名（aws-appの出力値） |
| `CodeDeployGroupName` | String | `""` | CodeDeployデプロイグループ名（aws-appの出力値） |

### Conditions

| 条件名 | 定義 |
|---|---|
| `IsCodeCommit` | `!Equals [!Ref SourceType, "codecommit"]` |
| `IsGitHub` | `!Equals [!Ref SourceType, "github"]` |

### 子スタックの展開順序

| 順序 | スタック論理ID | テンプレートファイル | 依存 |
|---|---|---|---|
| 1 | `EcrStack` | `stacks/01-ecr.yaml` | なし |
| 2 | `SourceCodeCommitStack` | `stacks/02-source-codecommit.yaml` | なし（`IsCodeCommit` が true の時のみ） |
| 2 | `SourceGitHubStack` | `stacks/02-source-github.yaml` | なし（`IsGitHub` が true の時のみ） |
| 3 | `IamStack` | `stacks/03-iam.yaml` | EcrStack, SourceStack |
| 4 | `PipelineStack` | `stacks/04-pipeline.yaml` | IamStack, EcrStack, SourceStack |

---

## 01-ecr.yaml

### Resources

#### ECR リポジトリ

| 論理ID | リソース型 | 設定項目 | 値 |
|---|---|---|---|
| `EcrRepository` | `AWS::ECR::Repository` | RepositoryName | `!Ref ProjectName` |
| | | ImageTagMutability | `MUTABLE` |
| | | ScanOnPush | `true` |

#### ECR ライフサイクルポリシー

| 論理ID | リソース型 | 設定項目 | 値 |
|---|---|---|---|
| `EcrLifecyclePolicy` | `AWS::ECR::LifecyclePolicy` | LifecyclePolicy | 最新10イメージを保持、11件目以降を自動削除 |

### Outputs

| 出力名 | 値 | Export名 |
|---|---|---|
| `EcrRepositoryUrl` | ECRリポジトリのURI | `!Sub "${ProjectName}-ecr-url"` |
| `EcrRepositoryArn` | ECRリポジトリのARN | `!Sub "${ProjectName}-ecr-arn"` |

---

## 02-source-codecommit.yaml（CodeCommit版のみデプロイ）

### Resources

#### CodeCommit リポジトリ

| 論理ID | リソース型 | 設定項目 | 値 |
|---|---|---|---|
| `CodeCommitRepository` | `AWS::CodeCommit::Repository` | RepositoryName | `!Ref ProjectName` |
| | | RepositoryDescription | `!Sub "${ProjectName} source repository"` |

### Outputs

| 出力名 | 値 | Export名 |
|---|---|---|
| `RepositoryName` | リポジトリ名 | `!Sub "${ProjectName}-codecommit-name"` |
| `RepositoryArn` | リポジトリARN | `!Sub "${ProjectName}-codecommit-arn"` |

---

## 02-source-github.yaml（GitHub版のみデプロイ）

### Resources

#### CodeStar Connections

| 論理ID | リソース型 | 設定項目 | 値 |
|---|---|---|---|
| `GitHubConnection` | `AWS::CodeStarConnections::Connection` | ConnectionName | `!Sub "${ProjectName}-github"` |
| | | ProviderType | `GitHub` |

> 初期ステータスは `PENDING`。デプロイ後にAWSコンソールで手動承認が必要。

### Outputs

| 出力名 | 値 | Export名 |
|---|---|---|
| `ConnectionArn` | CodeStar Connection ARN | `!Sub "${ProjectName}-connection-arn"` |

---

## 03-iam.yaml

### Parameters（子スタックへの入力）

| パラメータ名 | 渡し元 |
|---|---|
| `ProjectName` | root.yml |
| `SourceType` | root.yml |
| `EcrRepositoryArn` | 01-ecr.yaml の出力 |
| `CodeCommitRepositoryArn` | 02-source-codecommit.yaml の出力（CodeCommit版のみ） |
| `ConnectionArn` | 02-source-github.yaml の出力（GitHub版のみ） |

### Conditions

| 条件名 | 定義 |
|---|---|
| `IsCodeCommit` | `!Equals [!Ref SourceType, "codecommit"]` |
| `IsGitHub` | `!Equals [!Ref SourceType, "github"]` |

### Resources

#### CodePipeline 実行ロール

| 論理ID | リソース型 | 設定項目 | 値 |
|---|---|---|---|
| `CodePipelineRole` | `AWS::IAM::Role` | RoleName | `!Sub "${ProjectName}-codepipeline-role"` |
| | | AssumeRolePolicyDocument | 信頼サービス: `codepipeline.amazonaws.com` |

#### CodePipeline インラインポリシー

| ポリシー論理ID | 対象リソース | 許可アクション | 条件 |
|---|---|---|---|
| `S3ArtifactPolicy` | `arn:aws:s3:::${ProjectName}-pipeline-artifacts-*` | GetObject, GetObjectVersion, PutObject, GetBucketVersioning, ListBucket | 常時 |
| `CodeBuildPolicy` | CodeBuildプロジェクトARN | StartBuild, BatchGetBuilds | 常時 |
| `CodeDeployPolicy` | `*` | CreateDeployment, GetDeployment 他 + iam:PassRole | 常時 |
| `CodeCommitPolicy` | CodeCommitリポジトリARN | GetBranch, GetCommit 他 | `IsCodeCommit` が true |
| `CodeStarPolicy` | CodeStar Connection ARN | codestar-connections:UseConnection | `IsGitHub` が true |

> **CloudFormation での循環依存解消**: S3バケットARNをワイルドカード `${ProjectName}-pipeline-artifacts-*` でポリシーに記載するため、04-pipeline.yaml のS3バケット作成前にIAMロールを定義できる。

#### CodeBuild 実行ロール

| 論理ID | リソース型 | 設定項目 | 値 |
|---|---|---|---|
| `CodeBuildRole` | `AWS::IAM::Role` | RoleName | `!Sub "${ProjectName}-codebuild-role"` |
| | | AssumeRolePolicyDocument | 信頼サービス: `codebuild.amazonaws.com` |

#### CodeBuild インラインポリシー

| ポリシー論理ID | 対象リソース | 許可アクション | 条件 |
|---|---|---|---|
| `EcrAuthPolicy` | `*` | ecr:GetAuthorizationToken | 常時 |
| `EcrImagePolicy` | ECRリポジトリARN | BatchCheckLayerAvailability, PutImage, InitiateLayerUpload 他 | 常時 |
| `S3ArtifactPolicy` | `arn:aws:s3:::${ProjectName}-pipeline-artifacts-*/*` | GetObject, GetObjectVersion, PutObject | 常時 |
| `CloudWatchLogsPolicy` | `/codebuild/${ProjectName}*` | CreateLogGroup, CreateLogStream, PutLogEvents | 常時 |

#### EventBridge 実行ロール（CodeCommit版のみ）

| 論理ID | リソース型 | 設定項目 | 値 | 条件 |
|---|---|---|---|---|
| `EventBridgeRole` | `AWS::IAM::Role` | RoleName | `!Sub "${ProjectName}-eventbridge-role"` | `IsCodeCommit` |
| | | AssumeRolePolicyDocument | 信頼サービス: `events.amazonaws.com` | `IsCodeCommit` |
| `EventBridgePolicy` | インラインポリシー | codepipeline:StartPipelineExecution on `${ProjectName}-pipeline` | | `IsCodeCommit` |

### Outputs

| 出力名 | 値 | Export名 |
|---|---|---|
| `CodePipelineRoleArn` | CodePipeline ロール ARN | `!Sub "${ProjectName}-codepipeline-role-arn"` |
| `CodeBuildRoleArn` | CodeBuild ロール ARN | `!Sub "${ProjectName}-codebuild-role-arn"` |
| `EventBridgeRoleArn` | EventBridge ロール ARN（CodeCommit版のみ） | `!Sub "${ProjectName}-eventbridge-role-arn"` |

---

## 04-pipeline.yaml

### Parameters（子スタックへの入力）

| パラメータ名 | 渡し元 |
|---|---|
| `ProjectName` | root.yml |
| `AwsRegion` | root.yml |
| `SourceType` | root.yml |
| `CodeCommitRepoName` | 02-source-codecommit.yaml の出力（CodeCommit版のみ） |
| `CodeCommitBranch` | root.yml |
| `CodeCommitRepoArn` | 02-source-codecommit.yaml の出力（CodeCommit版のみ） |
| `ConnectionArn` | 02-source-github.yaml の出力（GitHub版のみ） |
| `GitHubOwner` | root.yml |
| `GitHubRepo` | root.yml |
| `GitHubBranch` | root.yml |
| `EcrRepositoryUrl` | 01-ecr.yaml の出力 |
| `CodePipelineRoleArn` | 03-iam.yaml の出力 |
| `CodeBuildRoleArn` | 03-iam.yaml の出力 |
| `EventBridgeRoleArn` | 03-iam.yaml の出力（CodeCommit版のみ） |
| `EcsClusterName` | root.yml |
| `EcsServiceName` | root.yml |
| `CodeDeployAppName` | root.yml |
| `CodeDeployGroupName` | root.yml |

### Conditions

| 条件名 | 定義 |
|---|---|
| `IsCodeCommit` | `!Equals [!Ref SourceType, "codecommit"]` |
| `IsGitHub` | `!Equals [!Ref SourceType, "github"]` |

### Resources

#### S3 アーティファクトバケット

| 論理ID | リソース型 | 設定項目 | 値 |
|---|---|---|---|
| `ArtifactBucket` | `AWS::S3::Bucket` | BucketName | `!Sub "${ProjectName}-pipeline-artifacts-${AWS::AccountId}"` |
| | | VersioningConfiguration | Status: `Enabled` |
| | | BucketEncryption | SSEAlgorithm: `AES256` |
| | | PublicAccessBlockConfiguration | 全項目 `true` |

#### CloudWatch Logs グループ

| 論理ID | リソース型 | 設定項目 | 値 |
|---|---|---|---|
| `CodeBuildLogGroup` | `AWS::Logs::LogGroup` | LogGroupName | `!Sub "/codebuild/${ProjectName}"` |
| | | RetentionInDays | `30` |

#### CodeBuild プロジェクト

| 論理ID | リソース型 | 設定項目 | 値 |
|---|---|---|---|
| `CodeBuildProject` | `AWS::CodeBuild::Project` | Name | `!Sub "${ProjectName}-build"` |
| | | ServiceRole | `!Ref CodeBuildRoleArn` |
| | | Source.Type | `CODEPIPELINE` |
| | | Source.BuildSpec | `buildspec.yml` |
| | | Artifacts.Type | `CODEPIPELINE` |
| | | Environment.ComputeType | `BUILD_GENERAL1_SMALL` |
| | | Environment.Image | `aws/codebuild/standard:7.0` |
| | | Environment.Type | `LINUX_CONTAINER` |
| | | Environment.PrivilegedMode | `true` |

#### CodeBuild 環境変数

| 変数名 | 値 |
|---|---|
| `ECR_REPOSITORY_URI` | `!Ref EcrRepositoryUrl` |
| `AWS_DEFAULT_REGION` | `!Ref AwsRegion` |
| `CONTAINER_NAME` | `!Ref ProjectName` |

#### CodePipeline

| 論理ID | リソース型 | 設定項目 | 値 |
|---|---|---|---|
| `Pipeline` | `AWS::CodePipeline::Pipeline` | Name | `!Sub "${ProjectName}-pipeline"` |
| | | RoleArn | `!Ref CodePipelineRoleArn` |
| | | ArtifactStore.Location | `!Ref ArtifactBucket` |
| | | ArtifactStore.Type | `S3` |

#### CodePipeline ステージ構成

| ステージ | アクション名 | プロバイダー | 入力 | 出力 | 条件 |
|---|---|---|---|---|---|
| Source | Source | CodeCommit | — | `source_output` | `IsCodeCommit` |
| Source | Source | CodeStarSourceConnection | — | `source_output` | `IsGitHub` |
| Build | Build | CodeBuild | `source_output` | `build_output` | 常時 |
| Deploy | Deploy | CodeDeployToECS | `build_output` | — | 常時 |

#### EventBridge ルール（CodeCommit版のみ）

| 論理ID | リソース型 | 設定項目 | 値 | 条件 |
|---|---|---|---|---|
| `CodeCommitEventRule` | `AWS::Events::Rule` | Name | `!Sub "${ProjectName}-codecommit-push"` | `IsCodeCommit` |
| | | EventPattern | source: `aws.codecommit`, referenceCreated/referenceUpdated, 対象ブランチ | `IsCodeCommit` |
| | | Targets | CodePipeline ARN, EventBridge ロール ARN | `IsCodeCommit` |

### Outputs

| 出力名 | 値 | Export名 |
|---|---|---|
| `PipelineName` | CodePipeline 名 | `!Sub "${ProjectName}-pipeline-name"` |
| `ArtifactBucketName` | S3バケット名 | `!Sub "${ProjectName}-artifact-bucket"` |
