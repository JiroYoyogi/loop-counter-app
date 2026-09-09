/**
 * GitHub App のインストールアクセストークンを取得して標準出力に返す。
 *
 * 使い方:
 *   npx tsx scripts/github-app-auth.ts
 *
 * 出力: 有効なインストールアクセストークンを1行だけ stdout に出力する。
 *       進捗・エラーは stderr に出す（stdout はトークン専用）。
 *
 * 設定はリポジトリ直下の .env（.env.example 参照）から読み込む:
 *   GITHUB_APP_ID
 *   GITHUB_APP_INSTALLATION_ID
 *   GITHUB_APP_PRIVATE_KEY_PATH        (.pem のパス。リポジトリ外に置く)
 *
 * 取得したトークンは ~/.config/github-apps/claude-code.token.json にキャッシュし、
 * 有効期限まで5分以上あれば再利用する（キャッシュ先はリポジトリ外に固定）。
 */

import { readFileSync, writeFileSync, mkdirSync, chmodSync, accessSync, statSync, constants } from "node:fs";
import { homedir } from "node:os";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { createAppAuth } from "@octokit/auth-app";
import { config as loadDotenv } from "dotenv";

const REPO_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..");
/** トークンキャッシュの保存先。リポジトリ外に固定（上書き設定は用意しない）。 */
const CACHE_PATH = "~/.config/github-apps/claude-code.token.json";
/** 有効期限までこの秒数を切っていたら再発行する。 */
const RENEW_BEFORE_SEC = 5 * 60;

/** 設定不備で終了するためのエラー。スタックトレースは出さない。 */
class ConfigError extends Error {}

function expandHome(p: string): string {
  if (p === "~") return homedir();
  if (p.startsWith("~/")) return resolve(homedir(), p.slice(2));
  return resolve(p);
}

function requireEnv(name: string): string {
  const v = process.env[name];
  if (!v || v.trim() === "") {
    throw new ConfigError(
      `環境変数 ${name} が未設定です。${REPO_ROOT}/.env を .env.example を参考に作成してください。`,
    );
  }
  return v.trim();
}

/**
 * トークンとして妥当な文字列か。空・空白のみ・空白や改行を含むものは不正とみなす。
 * 空トークンをそのまま返すと gh は「未設定」として保存済みの個人認証へ
 * フォールバックしてしまうため、ここで弾く。
 */
function isValidToken(v: unknown): v is string {
  return typeof v === "string" && v.trim() !== "" && !/\s/.test(v);
}

/**
 * 秘密鍵が「読み取り可能な通常ファイル」であることを確認する（内容は読まない）。
 * キャッシュヒット時でも設定不備をその場で検知するために使う。
 * accessSync だけだと読めるディレクトリでも成功してしまうため isFile() も見る。
 */
function assertPrivateKeyReadable(path: string): void {
  const abs = expandHome(path);
  try {
    accessSync(abs, constants.R_OK);
  } catch {
    throw new ConfigError(
      `秘密鍵を読み込めません: ${abs}\n` +
        `GITHUB_APP_PRIVATE_KEY_PATH のパスと、ファイルの存在・読み取り権限を確認してください。`,
    );
  }
  if (!statSync(abs).isFile()) {
    throw new ConfigError(
      `秘密鍵がファイルではありません: ${abs}\n` +
        `GITHUB_APP_PRIVATE_KEY_PATH には .pem ファイルのパスを指定してください。`,
    );
  }
}

function readPrivateKey(path: string): string {
  const abs = expandHome(path);
  try {
    return readFileSync(abs, "utf8");
  } catch {
    throw new ConfigError(
      `秘密鍵を読み込めません: ${abs}\n` +
        `GITHUB_APP_PRIVATE_KEY_PATH のパスと、ファイルの存在・読み取り権限を確認してください。`,
    );
  }
}

interface TokenCache {
  token: string;
  /** ISO8601。GitHub が返す expires_at をそのまま保持する。 */
  expiresAt: string;
  installationId: string;
}

function readCache(): TokenCache | null {
  try {
    const raw = readFileSync(expandHome(CACHE_PATH), "utf8");
    const parsed = JSON.parse(raw) as Partial<TokenCache>;
    if (
      isValidToken(parsed.token) &&
      typeof parsed.expiresAt === "string" &&
      typeof parsed.installationId === "string"
    ) {
      return parsed as TokenCache;
    }
    // 破損キャッシュ（空トークン等）はキャッシュミスとして扱い、再発行させる。
    return null;
  } catch {
    return null;
  }
}

function isFresh(cache: TokenCache, installationId: string): boolean {
  if (cache.installationId !== installationId) return false;
  const expiresMs = Date.parse(cache.expiresAt);
  if (Number.isNaN(expiresMs)) return false;
  const remainingSec = (expiresMs - Date.now()) / 1000;
  return remainingSec > RENEW_BEFORE_SEC;
}

function writeCache(cache: TokenCache): void {
  const abs = expandHome(CACHE_PATH);
  const dir = dirname(abs);
  mkdirSync(dir, { recursive: true, mode: 0o700 });
  // 既存ディレクトリには mkdir の mode が効かないため明示的に絞る。
  try {
    chmodSync(dir, 0o700);
  } catch {
    /* 権限変更できなくても致命的ではない */
  }
  writeFileSync(abs, JSON.stringify(cache, null, 2) + "\n", { mode: 0o600 });
  // mode は新規作成時のみ適用されるため、既存ファイルにも明示的に 0600 を適用。
  try {
    chmodSync(abs, 0o600);
  } catch {
    /* 権限変更できなくても致命的ではない */
  }
}

async function main(): Promise<void> {
  loadDotenv({ path: resolve(REPO_ROOT, ".env"), quiet: true });

  const appId = requireEnv("GITHUB_APP_ID");
  const installationId = requireEnv("GITHUB_APP_INSTALLATION_ID");
  const privateKeyPath = requireEnv("GITHUB_APP_PRIVATE_KEY_PATH");
  // キャッシュを返す場合でも先に検証する。ここを飛ばすと、鍵が削除・移動されても
  // キャッシュが切れるまで（最大1時間）成功し続け、設定不備の発覚が遅れる。
  assertPrivateKeyReadable(privateKeyPath);

  const cached = readCache();
  if (cached && isFresh(cached, installationId)) {
    process.stderr.write("cache hit: 未期限切れのトークンを再利用します\n");
    process.stdout.write(cached.token + "\n");
    return;
  }

  process.stderr.write("cache miss: インストールアクセストークンを新規発行します\n");
  const privateKey = readPrivateKey(privateKeyPath);
  const auth = createAppAuth({ appId, privateKey, installationId });

  let token: string;
  let expiresAt: string;
  try {
    const result = await auth({ type: "installation" });
    token = result.token;
    expiresAt = result.expiresAt;
  } catch (err) {
    const detail = err instanceof Error ? err.message : String(err);
    throw new ConfigError(
      `トークンの発行に失敗しました: ${detail}\n` +
        `App ID / インストール ID / 秘密鍵の対応関係と、App のインストール状態を確認してください。`,
    );
  }

  if (!isValidToken(token)) {
    throw new ConfigError("発行されたトークンが不正です（空、または空白を含む）。");
  }

  writeCache({ token, expiresAt, installationId });
  process.stderr.write(`発行しました（有効期限 ${expiresAt}）\n`);
  process.stdout.write(token + "\n");
}

main().catch((err) => {
  if (err instanceof ConfigError) {
    process.stderr.write(`\n[github-app-auth] ${err.message}\n`);
  } else {
    process.stderr.write(`\n[github-app-auth] 予期しないエラー:\n`);
    console.error(err);
  }
  process.exit(1);
});
