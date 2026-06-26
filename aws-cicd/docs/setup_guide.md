# CodeCommit 接続セットアップ手順書

## 概要

ローカル環境からAWS CodeCommitへコードをpushするための接続設定手順です。  
接続方式は **HTTPS + AWS CLI 認証情報ヘルパー** を使用します。

> **前提**: IaCのデプロイが完了していること。  
> CodeCommitリポジトリはIaC（`codecommit_repo_name` パラメータ）によって自動作成されます。

---

## 前提条件

| 項目 | 確認方法 |
|---|---|
| AWS CLI v2 インストール済み | `aws --version` |
| Git インストール済み | `git --version` |
| AWS 認証情報設定済み | `aws sts get-caller-identity` |
| CodeCommit 操作権限のある IAM ユーザー/ロール | AWS コンソールで確認 |
| IaC のデプロイ完了 | CodeCommitリポジトリが存在すること |

---

## Step 1: AWS アクセスキーを取得する（AWS コンソール操作）

AWS CLI の認証に使用するアクセスキーを IAM コンソールで発行します。

1. AWS コンソール → **IAM** → **ユーザー** → 対象ユーザーを選択
2. **セキュリティ認証情報** タブを開く
3. **アクセスキー** セクション → **アクセスキーを作成**
4. ユースケースで **コマンドラインインターフェイス (CLI)** を選択 → 次へ
5. **アクセスキー ID** と **シークレットアクセスキー** が表示される
   - この画面を閉じるとシークレットアクセスキーは二度と表示されないため、必ず控えること

---

## Step 2: AWS CLI の認証情報を設定する（ローカル操作）

取得したアクセスキーをローカル PC の AWS CLI に設定します。

```powershell
aws configure
```

```
AWS Access Key ID:     <Step1で取得したアクセスキーID>
AWS Secret Access Key: <Step1で取得したシークレットアクセスキー>
Default region name:   ap-northeast-1
Default output format: json
```

設定確認：

```powershell
aws sts get-caller-identity
```

アカウントIDとユーザー情報が表示されれば正常です。

---

## Step 3: Git の認証情報ヘルパーを設定する（ローカル操作）

CodeCommit への HTTPS 接続には AWS CLI の認証情報ヘルパーを使用します。

```powershell
git config --global credential.helper "!aws codecommit credential-helper $@"
git config --global credential.UseHttpPath true
```

設定確認：

```powershell
git config --global --list | Select-String "credential"
```

以下のように表示されれば正常です。

```
credential.helper=!aws codecommit credential-helper $@
credential.usehttppath=true
```

---

## Step 4: クローン URL を確認する（ローカル操作）

IaC デプロイ後に作成された CodeCommit リポジトリの URL を取得します。  
`<codecommit_repo_name>` はIaC デプロイ時に指定した `codecommit_repo_name` パラメータの値です。

```powershell
aws codecommit get-repository `
  --repository-name <codecommit_repo_name> `
  --region ap-northeast-1 `
  --query "repositoryMetadata.cloneUrlHttp" `
  --output text
```

出力例：
```
https://git-codecommit.ap-northeast-1.amazonaws.com/v1/repos/<codecommit_repo_name>
```

---

## Step 5: ローカルリポジトリと接続する（ローカル操作）

### 新規（クローン）の場合

```powershell
git clone https://git-codecommit.ap-northeast-1.amazonaws.com/v1/repos/<codecommit_repo_name>
cd <codecommit_repo_name>
```

### 既存ローカルリポジトリに remote を追加する場合

```powershell
git remote add origin https://git-codecommit.ap-northeast-1.amazonaws.com/v1/repos/<codecommit_repo_name>
```

remote 確認：

```powershell
git remote -v
```

---

## Step 6: コードを push する（ローカル操作）

```powershell
git add -A
git commit -m "initial commit"
git push origin main
```

---

## 動作確認

push 後、AWS コンソールで確認します。

1. AWS コンソール → **CodeCommit** → リポジトリ一覧
2. `<codecommit_repo_name>` を選択
3. コードが反映されていることを確認

---

## トラブルシューティング

### `fatal: repository not found` が出る場合

- IaC が正常にデプロイ完了しているか確認する
- `aws codecommit list-repositories --region ap-northeast-1` でリポジトリ一覧を確認する

### 認証エラーが出る場合

- `aws sts get-caller-identity` で認証情報が有効か確認する
- IAM ユーザー/ロールに `AWSCodeCommitPowerUser` ポリシーがあるか確認する

### credential helper が効かない場合

- Windows の資格情報マネージャーに古い CodeCommit の認証情報が残っている可能性があります
- コントロールパネル → 資格情報マネージャー → Windows 資格情報 → `git:https://git-codecommit` を削除して再試行する
