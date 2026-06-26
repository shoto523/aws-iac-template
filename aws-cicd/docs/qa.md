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
./deploy.sh `
  --project-name      <project_name> `
  --region            ap-northeast-1 `
  --ecs-cluster       既存のECSクラスター名 `
  --ecs-service       既存のECSサービス名 `
  --codedeploy-app    既存のCodeDeployアプリ名 `
  --codedeploy-group  既存のCodeDeployデプロイグループ名
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
