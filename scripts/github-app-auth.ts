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
 *   GITHUB_APP_TOKEN_CACHE_PATH        (任意。既定 ~/.config/github-apps/claude-code.token.json)
 *
 * 取得したトークンはキャッシュし、有効期限まで5分以上あれば再利用する。
 */

import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { createAppAuth } from "@octokit/auth-app";
import { config as loadDotenv } from "dotenv";

const REPO_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const DEFAULT_CACHE_PATH = "~/.config/github-apps/claude-code.token.json";
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

function readCache(path: string): TokenCache | null {
  try {
    const raw = readFileSync(expandHome(path), "utf8");
    const parsed = JSON.parse(raw) as Partial<TokenCache>;
    if (
      typeof parsed.token === "string" &&
      typeof parsed.expiresAt === "string" &&
      typeof parsed.installationId === "string"
    ) {
      return parsed as TokenCache;
    }
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

function writeCache(path: string, cache: TokenCache): void {
  const abs = expandHome(path);
  mkdirSync(dirname(abs), { recursive: true });
  writeFileSync(abs, JSON.stringify(cache, null, 2) + "\n", { mode: 0o600 });
}

async function main(): Promise<void> {
  loadDotenv({ path: resolve(REPO_ROOT, ".env"), quiet: true });

  const appId = requireEnv("GITHUB_APP_ID");
  const installationId = requireEnv("GITHUB_APP_INSTALLATION_ID");
  const privateKeyPath = requireEnv("GITHUB_APP_PRIVATE_KEY_PATH");
  const cachePath = process.env.GITHUB_APP_TOKEN_CACHE_PATH?.trim() || DEFAULT_CACHE_PATH;

  const cached = readCache(cachePath);
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

  writeCache(cachePath, { token, expiresAt, installationId });
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
