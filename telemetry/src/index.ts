interface Env {
  DB: D1Database;
  /** Cloudflare Worker secret. Never commit the Discord webhook itself. */
  DISCORD_WEBHOOK_URL?: string;
  /** Compatibility name for the previously deployed Worker secret. */
  DISCORD_WEBHOOK?: string;
  /** Hashes the random installation identifier before it reaches D1. */
  PEPPER?: string;
  /** Name used by the previously deployed Worker secret. */
  TELEMETRY_PEPPER?: string;
  /** Protects the optional /stats endpoint. */
  STATS_TOKEN?: string;
}

type InstallPayload = {
  installation_id?: unknown;
  app?: {
    version?: unknown;
    build?: unknown;
    platform?: unknown;
  };
  system?: {
    os?: unknown;
    architecture?: unknown;
    locale?: unknown;
    model?: unknown;
  };
};

const json = (status: number, body: Record<string, unknown>) =>
  new Response(JSON.stringify(body), {
    status,
    headers: {
      'content-type': 'application/json; charset=utf-8',
      'cache-control': 'no-store',
    },
  });

const installationIdPattern = /^YOM-[A-F0-9]{32}$/;
const simpleValuePattern = /^[\p{L}\p{N} ._+\-(),/]{1,80}$/u;

export default {
  async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    const url = new URL(request.url);
    if (request.method === 'GET' && url.pathname === '/health') {
      return json(200, { ok: true });
    }
    if (request.method === 'GET' && url.pathname === '/stats') {
      if (!isAdmin(request, env)) return json(401, { error: 'unauthorized' });
      await ensureSchema(env.DB);
      const today = new Date().toISOString().slice(0, 10);
      const [total, todayTotal, platforms] = await env.DB.batch([
        env.DB.prepare('SELECT COUNT(*) AS total FROM telemetry_installations_v1'),
        env.DB
          .prepare('SELECT COUNT(*) AS total FROM telemetry_installations_v1 WHERE first_seen >= ?')
          .bind(today),
        env.DB.prepare(
          'SELECT platform, COUNT(*) AS total FROM telemetry_installations_v1 GROUP BY platform ORDER BY total DESC',
        ),
      ]);
      return json(200, {
        total: (total.results[0] as { total?: number } | undefined)?.total ?? 0,
        today: (todayTotal.results[0] as { total?: number } | undefined)?.total ?? 0,
        platforms: platforms.results,
      });
    }
    if (request.method !== 'POST' || url.pathname !== '/v1/install') {
      return json(404, { error: 'not_found' });
    }
    if (!request.headers.get('content-type')?.toLowerCase().includes('application/json')) {
      return json(415, { error: 'json_required' });
    }

    let payload: InstallPayload;
    try {
      const raw = await request.text();
      if (raw.length > 2048) return json(413, { error: 'payload_too_large' });
      payload = JSON.parse(raw) as InstallPayload;
    } catch {
      return json(400, { error: 'invalid_json' });
    }

    const installationId = stringValue(payload.installation_id, 40);
    const version = stringValue(payload.app?.version, 32);
    const build = stringValue(payload.app?.build, 32);
    const platform = stringValue(payload.app?.platform, 16).toLowerCase();
    const os = stringValue(payload.system?.os, 80);
    const architecture = stringValue(payload.system?.architecture, 32);
    const locale = stringValue(payload.system?.locale, 32);
    const model = stringValue(payload.system?.model, 80);

    if (
      !installationIdPattern.test(installationId) ||
      !simpleValuePattern.test(version) ||
      !simpleValuePattern.test(build) ||
      !['android', 'ios'].includes(platform) ||
      !simpleValuePattern.test(os) ||
      !simpleValuePattern.test(architecture) ||
      !simpleValuePattern.test(locale) ||
      !simpleValuePattern.test(model)
    ) {
      return json(400, { error: 'invalid_payload' });
    }
    const pepper = env.TELEMETRY_PEPPER ?? env.PEPPER;
    if (!pepper) return json(503, { error: 'service_unavailable' });

    await ensureSchema(env.DB);
    const installationHash = await hashInstallationId(installationId, pepper);

    // 已知安装标识直接确认，不消耗 IP 限额，也不重复通知。
    const prior = await env.DB
      .prepare('SELECT installation_hash FROM telemetry_installations_v1 WHERE installation_hash = ?')
      .bind(installationHash)
      .first();
    if (prior) return json(200, { ok: true, recorded: false });

    // 仅在 Cloudflare Cache 中保留 5 分钟、不可逆哈希后的来源标记；不写入 D1，
    // 以降低脚本被伪造时对 Discord 和数据库的滥用。
    if (!(await reserveRateLimit(request))) {
      return json(429, { error: 'rate_limited' });
    }

    const now = new Date().toISOString();
    const inserted = await env.DB
      .prepare(
        `INSERT OR IGNORE INTO telemetry_installations_v1
          (installation_hash, app_version, build_number, platform, os_name, architecture, locale, model, first_seen)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      )
      .bind(installationHash, version, build, platform, os, architecture, locale, model, now)
      .run();
    if ((inserted.meta.changes ?? 0) !== 1) {
      return json(200, { ok: true, recorded: false });
    }

    // 即使有人批量伪造请求，也限制每日 Discord 通知数；统计记录本身不受影响。
    const today = now.slice(0, 10);
    const count = await env.DB
      .prepare('SELECT COUNT(*) AS total FROM telemetry_installations_v1 WHERE first_seen >= ?')
      .bind(today)
      .first<{ total: number }>();
    const webhook = env.DISCORD_WEBHOOK_URL ?? env.DISCORD_WEBHOOK;
    if ((count?.total ?? 0) <= 400 && webhook) {
      ctx.waitUntil(notifyDiscord(webhook, {
        installationId,
        version,
        build,
        platform,
        os,
        architecture,
        locale,
        model,
        now,
      }));
    }

    return json(201, { ok: true, recorded: true });
  },
};

async function ensureSchema(db: D1Database): Promise<void> {
  await db.batch([
    db.prepare(
      `CREATE TABLE IF NOT EXISTS telemetry_installations_v1 (
        installation_hash TEXT PRIMARY KEY,
        app_version TEXT NOT NULL,
        build_number TEXT NOT NULL,
        platform TEXT NOT NULL,
        os_name TEXT NOT NULL,
        architecture TEXT NOT NULL,
        locale TEXT NOT NULL,
        model TEXT NOT NULL,
        first_seen TEXT NOT NULL
      )`,
    ),
    db.prepare(
      'CREATE INDEX IF NOT EXISTS telemetry_installations_v1_first_seen ON telemetry_installations_v1(first_seen)',
    ),
  ]);
}

function isAdmin(request: Request, env: Env): boolean {
  const authorization = request.headers.get('authorization') ?? '';
  return Boolean(env.STATS_TOKEN) && authorization === `Bearer ${env.STATS_TOKEN}`;
}

async function hashInstallationId(installationId: string, pepper: string): Promise<string> {
  return sha256(`${pepper}:${installationId}`);
}

async function reserveRateLimit(request: Request): Promise<boolean> {
  const ip = request.headers.get('CF-Connecting-IP') ?? 'unknown';
  const source = await sha256(`yomiru-install-v1:${ip}`);
  const key = new Request(`https://rate-limit.invalid/yomiru/install/${source}`);
  if (await caches.default.match(key)) return false;
  await caches.default.put(
    key,
    new Response('1', { headers: { 'cache-control': 'max-age=300' } }),
  );
  return true;
}

async function sha256(input: string): Promise<string> {
  const bytes = new TextEncoder().encode(input);
  const digest = await crypto.subtle.digest('SHA-256', bytes);
  return [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, '0')).join('');
}

function stringValue(value: unknown, maxLength: number): string {
  if (typeof value !== 'string') return '';
  const compact = value.replace(/[\u0000-\u001F\u007F]/g, ' ').trim().replace(/\s+/g, ' ');
  return compact.length <= maxLength ? compact : '';
}

async function notifyDiscord(
  webhook: string,
  event: {
    installationId: string;
    version: string;
    build: string;
    platform: string;
    os: string;
    architecture: string;
    locale: string;
    model: string;
    now: string;
  },
): Promise<void> {
  const platform = event.platform === 'ios' ? 'iOS' : 'Android';
  await fetch(webhook, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({
      content: [
        '🌷 **Yomiru 有新人加入！**',
        `版本：${platform} ${event.version} (${event.build})`,
        `系统标识：${event.installationId}`,
        `系统：${event.os} ${event.architecture} ${event.locale}`,
        `设备：${event.model}`,
        `UTC：${event.now}`,
      ].join('\n'),
      allowed_mentions: { parse: [] },
    }),
  });
}
