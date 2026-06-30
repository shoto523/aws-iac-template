# リソース詳細設計書 - CloudFormation版（aws-app）

CloudFormation スタックは未実装のため、design.md と Terraform 版 resource_design.md を元にした設計仕様。  
実装時にはこの仕様に従ってスタックを作成し、完了後に実コードと照合して更新する。

`${ProjectName}` は `root.yml` の `Parameters` セクションからすべての子スタックに渡される値。

---

## root.yml（ネストスタック頂点）

### Parameters（入力パラメータ）

| パラメータ名 | 型 | デフォルト | 説明 |
|---|---|---|---|
| `ProjectName` | String | — | リソース名プレフィックス |
| `VpcId` | String | — | ECS・ALBを配置するVPC ID |
| `PublicSubnetIds` | CommaDelimitedList | — | ALBを配置するパブリックサブネットID（複数） |
| `PrivateSubnetIds` | CommaDelimitedList | — | ECSタスクを配置するプライベートサブネットID（複数） |
| `AlbSecurityGroupId` | String | — | ALB用セキュリティグループID |
| `EcsSecurityGroupId` | String | — | ECSタスク用セキュリティグループID |
| `ContainerName` | String | — | タスク定義のコンテナ名 |
| `ContainerPort` | Number | `80` | コンテナが使用するポート番号 |
| `EcrRepositoryUrl` | String | — | ECRリポジトリURI（aws-cicdの出力値） |

### 子スタックの展開順序

| 順序 | スタック論理ID | テンプレートファイル | 依存 |
|---|---|---|---|
| 1 | `IamStack` | `stacks/01-iam.yaml` | なし |
| 2 | `AlbStack` | `stacks/02-alb.yaml` | なし |
| 3 | `EcsStack` | `stacks/03-ecs.yaml` | IamStack, AlbStack |
| 4 | `CodeDeployStack` | `stacks/04-codedeploy.yaml` | IamStack, AlbStack, EcsStack |

---

## 01-iam.yaml

### Resources

#### ECS Task Execution ロール

| 論理ID | リソース型 | 設定項目 | 値 |
|---|---|---|---|
| `EcsTaskExecutionRole` | `AWS::IAM::Role` | RoleName | `!Sub "${ProjectName}-ecs-task-execution-role"` |
| | | AssumeRolePolicyDocument | 信頼サービス: `ecs-tasks.amazonaws.com` |

#### ECS Task Execution インラインポリシー

| ポリシー論理ID | 対象リソース | 許可アクション |
|---|---|---|
| `EcrAuthPolicy` | `*` | ecr:GetAuthorizationToken |
| `EcrImagePolicy` | ECRリポジトリARN | BatchGetImage, GetDownloadUrlForLayer, BatchCheckLayerAvailability |
| `CloudWatchLogsPolicy` | `/ecs/${ProjectName}*` | CreateLogGroup, CreateLogStream, PutLogEvents |

#### ECS Task ロール

| 論理ID | リソース型 | 設定項目 | 値 |
|---|---|---|---|
| `EcsTaskRole` | `AWS::IAM::Role` | RoleName | `!Sub "${ProjectName}-ecs-task-role"` |
| | | AssumeRolePolicyDocument | 信頼サービス: `ecs-tasks.amazonaws.com` |
| | | インラインポリシー | なし（アプリ要件に応じて追加） |

#### CodeDeploy 実行ロール

| 論理ID | リソース型 | 設定項目 | 値 |
|---|---|---|---|
| `CodeDeployRole` | `AWS::IAM::Role` | RoleName | `!Sub "${ProjectName}-codedeploy-role"` |
| | | AssumeRolePolicyDocument | 信頼サービス: `codedeploy.amazonaws.com` |

#### CodeDeploy インラインポリシー

| ポリシー論理ID | 対象リソース | 許可アクション |
|---|---|---|
| `EcsPolicy` | `*` | DescribeServices, UpdateService, RegisterTaskDefinition 他 |
| `AlbPolicy` | `*` | DescribeTargetGroups, ModifyListener, ModifyRule 他 |
| `IamPassRolePolicy` | `*` | iam:PassRole |
| `S3Policy` | `arn:aws:s3:::*-pipeline-artifacts-*/*` | s3:GetObject |

### Outputs

| 出力名 | 値 | Export名 |
|---|---|---|
| `EcsTaskExecutionRoleArn` | Task Execution ロール ARN | `!Sub "${ProjectName}-task-execution-role-arn"` |
| `EcsTaskRoleArn` | Task ロール ARN | `!Sub "${ProjectName}-task-role-arn"` |
| `CodeDeployRoleArn` | CodeDeploy ロール ARN | `!Sub "${ProjectName}-codedeploy-role-arn"` |

---

## 02-alb.yaml

### Resources

#### ALB

| 論理ID | リソース型 | 設定項目 | 値 |
|---|---|---|---|
| `Alb` | `AWS::ElasticLoadBalancingV2::LoadBalancer` | Name | `!Sub "${ProjectName}-alb"` |
| | | Type | `application` |
| | | Scheme | `internet-facing` |
| | | Subnets | `!Ref PublicSubnetIds` |
| | | SecurityGroups | `[!Ref AlbSecurityGroupId]` |

#### Target Group（Blue）

| 論理ID | リソース型 | 設定項目 | 値 |
|---|---|---|---|
| `TargetGroupBlue` | `AWS::ElasticLoadBalancingV2::TargetGroup` | Name | `!Sub "${ProjectName}-tg-blue"` |
| | | TargetType | `ip`（Fargate使用のため） |
| | | Protocol | `HTTP` |
| | | Port | `!Ref ContainerPort` |
| | | VpcId | `!Ref VpcId` |

#### Target Group（Green）

| 論理ID | リソース型 | 設定項目 | 値 |
|---|---|---|---|
| `TargetGroupGreen` | `AWS::ElasticLoadBalancingV2::TargetGroup` | Name | `!Sub "${ProjectName}-tg-green"` |
| | | TargetType | `ip` |
| | | Protocol | `HTTP` |
| | | Port | `!Ref ContainerPort` |
| | | VpcId | `!Ref VpcId` |

#### Listener（本番 :80）

| 論理ID | リソース型 | 設定項目 | 値 |
|---|---|---|---|
| `ListenerProd` | `AWS::ElasticLoadBalancingV2::Listener` | LoadBalancerArn | `!Ref Alb` |
| | | Port | `80` |
| | | Protocol | `HTTP` |
| | | DefaultActions | forward → `TargetGroupBlue` |

#### Listener（テスト :8080）

| 論理ID | リソース型 | 設定項目 | 値 |
|---|---|---|---|
| `ListenerTest` | `AWS::ElasticLoadBalancingV2::Listener` | LoadBalancerArn | `!Ref Alb` |
| | | Port | `8080` |
| | | Protocol | `HTTP` |
| | | DefaultActions | forward → `TargetGroupGreen` |

### Outputs

| 出力名 | 値 | Export名 |
|---|---|---|
| `AlbDnsName` | ALB の DNS 名 | `!Sub "${ProjectName}-alb-dns"` |
| `AlbArn` | ALB ARN | `!Sub "${ProjectName}-alb-arn"` |
| `ListenerProdArn` | 本番リスナー ARN | `!Sub "${ProjectName}-listener-prod-arn"` |
| `ListenerTestArn` | テストリスナー ARN | `!Sub "${ProjectName}-listener-test-arn"` |
| `TargetGroupBlueArn` | Blue ターゲットグループ ARN | `!Sub "${ProjectName}-tg-blue-arn"` |
| `TargetGroupGreenArn` | Green ターゲットグループ ARN | `!Sub "${ProjectName}-tg-green-arn"` |

---

## 03-ecs.yaml

### Resources

#### ECS Cluster

| 論理ID | リソース型 | 設定項目 | 値 |
|---|---|---|---|
| `EcsCluster` | `AWS::ECS::Cluster` | ClusterName | `!Sub "${ProjectName}-cluster"` |

#### ECS Task Definition

| 論理ID | リソース型 | 設定項目 | 値 |
|---|---|---|---|
| `TaskDefinition` | `AWS::ECS::TaskDefinition` | Family | `!Ref ProjectName` |
| | | NetworkMode | `awsvpc` |
| | | RequiresCompatibilities | `[FARGATE]` |
| | | Cpu | `256` |
| | | Memory | `512` |
| | | ExecutionRoleArn | ECS Task Execution ロール ARN（01-iam.yaml の出力） |
| | | TaskRoleArn | ECS Task ロール ARN（01-iam.yaml の出力） |

#### コンテナ定義

| 設定項目 | 値 |
|---|---|
| Name | `!Ref ContainerName` |
| Image | `!Sub "${EcrRepositoryUrl}:latest"` |
| PortMappings | ContainerPort: `!Ref ContainerPort`, Protocol: `tcp` |
| LogDriver | `awslogs` |
| LogGroup | `!Sub "/ecs/${ProjectName}"` |
| LogStreamPrefix | `ecs` |

#### ECS Service

| 論理ID | リソース型 | 設定項目 | 値 |
|---|---|---|---|
| `EcsService` | `AWS::ECS::Service` | ServiceName | `!Sub "${ProjectName}-service"` |
| | | Cluster | `!Ref EcsCluster` |
| | | LaunchType | `FARGATE` |
| | | DeploymentController | `CODE_DEPLOY` |
| | | DesiredCount | `1` |
| | | Subnets | `!Ref PrivateSubnetIds` |
| | | SecurityGroups | `[!Ref EcsSecurityGroupId]` |
| | | AssignPublicIp | `DISABLED` |
| | | LoadBalancer（ターゲットグループ） | Blue ターゲットグループ |

### Outputs

| 出力名 | 値 | Export名 |
|---|---|---|
| `EcsClusterName` | クラスター名 | `!Sub "${ProjectName}-cluster-name"` |
| `EcsServiceName` | サービス名 | `!Sub "${ProjectName}-service-name"` |

---

## 04-codedeploy.yaml

### Resources

#### CodeDeploy Application

| 論理ID | リソース型 | 設定項目 | 値 |
|---|---|---|---|
| `CodeDeployApp` | `AWS::CodeDeploy::Application` | ApplicationName | `!Sub "${ProjectName}-deploy"` |
| | | ComputePlatform | `ECS` |

#### CodeDeploy Deployment Group

| 論理ID | リソース型 | 設定項目 | 値 |
|---|---|---|---|
| `DeploymentGroup` | `AWS::CodeDeploy::DeploymentGroup` | ApplicationName | `!Ref CodeDeployApp` |
| | | DeploymentGroupName | `!Sub "${ProjectName}-deploy-group"` |
| | | ServiceRoleArn | CodeDeploy ロール ARN（01-iam.yaml の出力） |
| | | DeploymentConfigName | `CodeDeployDefault.ECSAllAtOnce` |
| | | DeploymentStyle.DeploymentType | `BLUE_GREEN` |
| | | DeploymentStyle.DeploymentOption | `WITH_TRAFFIC_CONTROL` |
| | | EcsServices.ClusterName | `${ProjectName}-cluster` |
| | | EcsServices.ServiceName | `${ProjectName}-service` |
| | | LoadBalancerInfo.TargetGroupPairInfoList | Blue/Green ターゲットグループ + 本番/テストリスナー |
| | | BlueGreenDeploymentConfiguration.TerminateBlueInstancesOnDeploymentSuccess | 5分後に終了 |

### Outputs

| 出力名 | 値 | Export名 |
|---|---|---|
| `CodeDeployAppName` | CodeDeploy アプリ名 | `!Sub "${ProjectName}-codedeploy-app-name"` |
| `CodeDeployGroupName` | デプロイグループ名 | `!Sub "${ProjectName}-codedeploy-group-name"` |
