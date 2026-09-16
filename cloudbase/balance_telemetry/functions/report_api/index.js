'use strict';

const REPORT_COLLECTION = 'run_reports';
const MAX_BODY_BYTES = 128 * 1024;
const MAX_DUELS = 256;
const MAX_EXPORT_REPORTS = 5000;
const ID_PATTERN = /^[a-z]+_[0-9a-f]{32}$/;
const CATALOG_ID_PATTERN = /^[A-Za-z0-9_]+$/;

function response(statusCode, body, contentType = 'application/json; charset=utf-8') {
  return {
    statusCode,
    headers: {
      'content-type': contentType,
      'cache-control': 'no-store',
    },
    body: typeof body === 'string' ? body : JSON.stringify(body),
  };
}

function normalizedHeaders(event) {
  const result = {};
  for (const [key, value] of Object.entries(event.headers || {})) {
    result[String(key).toLowerCase()] = String(value);
  }
  return result;
}

function requestMethod(event) {
  return String(
    event.httpMethod ||
    event.requestContext?.http?.method ||
    event.method ||
    ''
  ).toUpperCase();
}

function requestPath(event) {
  return String(event.rawPath || event.path || event.requestContext?.http?.path || '/');
}

function rawRequestBody(event) {
  if (typeof event.body === 'string') {
    return event.isBase64Encoded
      ? Buffer.from(event.body, 'base64').toString('utf8')
      : event.body;
  }
  if (event.body && typeof event.body === 'object') {
    return JSON.stringify(event.body);
  }
  return '';
}

function isIntegerInRange(value, minimum, maximum) {
  return Number.isInteger(value) && value >= minimum && value <= maximum;
}

function isShortString(value, maximum, pattern = null) {
  return (
    typeof value === 'string' &&
    value.length > 0 &&
    value.length <= maximum &&
    (pattern === null || pattern.test(value))
  );
}

function sanitizeCardIds(value) {
  if (!Array.isArray(value) || value.length !== 5) {
    return null;
  }
  const result = [];
  for (const cardId of value) {
    if (!isShortString(cardId, 64, CATALOG_ID_PATTERN)) {
      return null;
    }
    result.push(cardId);
  }
  return result;
}

function sanitizeDuel(value, expectedIndex) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    return null;
  }
  const playerCards = sanitizeCardIds(value.player_card_ids);
  const enemyCards = sanitizeCardIds(value.enemy_card_ids);
  if (
    value.duel_index !== expectedIndex ||
    !isShortString(value.enemy_id, 64, CATALOG_ID_PATTERN) ||
    !isIntegerInRange(value.player_level, 0, 15) ||
    ![1, 2].includes(value.starting_owner) ||
    !['victory', 'defeat'].includes(value.outcome) ||
    typeof value.counts_for_progress !== 'boolean' ||
    !isIntegerInRange(value.started_at, 0, Number.MAX_SAFE_INTEGER) ||
    !isIntegerInRange(value.completed_at, 0, Number.MAX_SAFE_INTEGER) ||
    playerCards === null ||
    enemyCards === null
  ) {
    return null;
  }
  return {
    duel_index: expectedIndex,
    enemy_id: value.enemy_id,
    player_level: value.player_level,
    starting_owner: value.starting_owner,
    outcome: value.outcome,
    counts_for_progress: value.counts_for_progress,
    started_at: value.started_at,
    completed_at: value.completed_at,
    player_card_ids: playerCards,
    enemy_card_ids: enemyCards,
  };
}

function sanitizeReport(value, receivedAt) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    return { error: 'report must be an object' };
  }
  if (
    value.schema_version !== 1 ||
    !isShortString(value.report_id, 64, ID_PATTERN) ||
    !isShortString(value.anonymous_player_id, 64, ID_PATTERN) ||
    !isShortString(value.run_id, 64, ID_PATTERN) ||
    typeof value.game_version !== 'string' || value.game_version.length > 32 ||
    !['Windows', 'Android'].includes(value.platform) ||
    !isIntegerInRange(value.difficulty, 0, 10) ||
    !isShortString(value.sect_id, 64, CATALOG_ID_PATTERN) ||
    !isIntegerInRange(value.final_score, 0, 1000000000) ||
    !isIntegerInRange(value.victory_count, 0, MAX_DUELS) ||
    !isIntegerInRange(value.defeat_count, 0, MAX_DUELS) ||
    !isIntegerInRange(value.formal_victory_count, 0, MAX_DUELS) ||
    !isIntegerInRange(value.formal_defeat_count, 0, MAX_DUELS) ||
    !isIntegerInRange(value.started_at, 0, Number.MAX_SAFE_INTEGER) ||
    !isIntegerInRange(value.completed_at, 0, Number.MAX_SAFE_INTEGER) ||
    !Array.isArray(value.duels) ||
    value.duels.length < 1 ||
    value.duels.length > MAX_DUELS
  ) {
    return { error: 'report fields are invalid' };
  }

  const duels = [];
  for (let index = 0; index < value.duels.length; index += 1) {
    const duel = sanitizeDuel(value.duels[index], index + 1);
    if (duel === null) {
      return { error: `duel ${index + 1} is invalid` };
    }
    duels.push(duel);
  }
  const victories = duels.filter((duel) => duel.outcome === 'victory').length;
  const defeats = duels.length - victories;
  const formalVictories = duels.filter(
    (duel) => duel.counts_for_progress && duel.outcome === 'victory'
  ).length;
  const formalDefeats = duels.filter(
    (duel) => duel.counts_for_progress && duel.outcome === 'defeat'
  ).length;
  if (
    value.victory_count !== victories ||
    value.defeat_count !== defeats ||
    value.formal_victory_count !== formalVictories ||
    value.formal_defeat_count !== formalDefeats
  ) {
    return { error: 'reported totals do not match duel outcomes' };
  }

  return {
    report: {
      _id: value.report_id,
      schema_version: 1,
      report_id: value.report_id,
      anonymous_player_id: value.anonymous_player_id,
      run_id: value.run_id,
      game_version: value.game_version,
      platform: value.platform,
      difficulty: value.difficulty,
      sect_id: value.sect_id,
      final_score: value.final_score,
      victory_count: victories,
      defeat_count: defeats,
      formal_victory_count: formalVictories,
      formal_defeat_count: formalDefeats,
      started_at: value.started_at,
      completed_at: value.completed_at,
      received_at: receivedAt,
      duels,
    },
  };
}

function parseQuery(event) {
  if (event.queryStringParameters && typeof event.queryStringParameters === 'object') {
    return event.queryStringParameters;
  }
  const raw = String(event.rawQueryString || '');
  return Object.fromEntries(new URLSearchParams(raw));
}

function csvCell(value) {
  const text = String(value ?? '');
  return /[",\r\n]/.test(text) ? `"${text.replaceAll('"', '""')}"` : text;
}

function reportsToCsv(reports) {
  const header = [
    'report_id', 'anonymous_player_id', 'game_version', 'platform', 'difficulty',
    'sect_id', 'final_score', 'victory_count', 'defeat_count',
    'formal_victory_count', 'formal_defeat_count', 'started_at', 'completed_at',
    'received_at', 'duel_index', 'enemy_id', 'player_level', 'starting_owner',
    'outcome', 'counts_for_progress',
    'player_card_1', 'player_card_2', 'player_card_3', 'player_card_4', 'player_card_5',
    'enemy_card_1', 'enemy_card_2', 'enemy_card_3', 'enemy_card_4', 'enemy_card_5',
  ];
  const rows = [header];
  for (const report of reports) {
    for (const duel of report.duels || []) {
      rows.push([
        report.report_id, report.anonymous_player_id, report.game_version,
        report.platform, report.difficulty, report.sect_id, report.final_score,
        report.victory_count, report.defeat_count, report.formal_victory_count,
        report.formal_defeat_count, report.started_at, report.completed_at,
        report.received_at, duel.duel_index, duel.enemy_id, duel.player_level,
        duel.starting_owner, duel.outcome, duel.counts_for_progress,
        ...(duel.player_card_ids || []), ...(duel.enemy_card_ids || []),
      ]);
    }
  }
  return `\uFEFF${rows.map((row) => row.map(csvCell).join(',')).join('\r\n')}\r\n`;
}

function isIsoDate(value) {
  return typeof value === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(value);
}

function matchesGatewayRoute(path, fullPath, relativePath) {
  // CloudBase event invocation preserves the configured prefix, while HTTP
  // Access Service removes that prefix before forwarding to an Event function.
  return path === fullPath || path === relativePath;
}

async function handleRequest(event, dependencies) {
  const method = requestMethod(event);
  const path = requestPath(event);
  const repository = dependencies.repository;
  const now = dependencies.now || (() => new Date().toISOString());

  if (method === 'POST' && matchesGatewayRoute(path, '/v1/reports', '/reports')) {
    const headers = normalizedHeaders(event);
    if (!headers['content-type']?.toLowerCase().startsWith('application/json')) {
      return response(415, { error: 'application/json is required' });
    }
    const rawBody = rawRequestBody(event);
    if (Buffer.byteLength(rawBody, 'utf8') > MAX_BODY_BYTES) {
      return response(413, { error: 'report is too large' });
    }
    let parsed;
    try {
      parsed = JSON.parse(rawBody);
    } catch (_error) {
      return response(400, { error: 'invalid JSON' });
    }
    const validation = sanitizeReport(parsed, now());
    if (validation.error) {
      return response(400, { error: validation.error });
    }
    const stored = await repository.create(validation.report);
    if (stored === 'duplicate') {
      return response(409, { ok: true, duplicate: true });
    }
    return response(201, { ok: true, report_id: validation.report.report_id });
  }

  if (
    method === 'GET' &&
    matchesGatewayRoute(path, '/v1/admin/export', '/admin/export')
  ) {
    const expectedToken = String(dependencies.adminToken || '');
    const authorization = normalizedHeaders(event).authorization || '';
    if (!expectedToken || authorization !== `Bearer ${expectedToken}`) {
      return response(401, { error: 'unauthorized' });
    }
    const query = parseQuery(event);
    const format = String(query.format || 'json').toLowerCase();
    if (!['csv', 'json'].includes(format)) {
      return response(400, { error: 'format must be csv or json' });
    }
    if ((query.from && !isIsoDate(query.from)) || (query.to && !isIsoDate(query.to))) {
      return response(400, { error: 'dates must use YYYY-MM-DD' });
    }
    const listed = await repository.list({
      from: query.from || '',
      to: query.to || '',
      limit: MAX_EXPORT_REPORTS,
    });
    if (listed.truncated) {
      return response(413, { error: 'date range contains too many reports; narrow it' });
    }
    if (format === 'csv') {
      return response(200, reportsToCsv(listed.reports), 'text/csv; charset=utf-8');
    }
    return response(200, { reports: listed.reports });
  }

  return response(404, { error: 'not found' });
}

function isDuplicateError(error) {
  const text = `${error?.code || ''} ${error?.message || ''}`.toLowerCase();
  return text.includes('duplicate') || text.includes('already exists') || text.includes('11000');
}

function cloudbaseInitOptions(cloudbase, environment = process.env) {
  return {
    env: cloudbase.SYMBOL_CURRENT_ENV,
    endPointMode: 'CLOUD_API',
    secretId: environment.TENCENTCLOUD_SECRETID,
    secretKey: environment.TENCENTCLOUD_SECRETKEY,
    sessionToken: environment.TENCENTCLOUD_SESSIONTOKEN,
  };
}

function createCloudRepository() {
  const cloudbase = require('@cloudbase/js-sdk');
  // 管理端数据库访问固定走 CLOUD_API，并显式传入事件云函数当前实例的
  // 临时三元组；默认 GATEWAY 或隐式发现路径无法可靠完成管理签名。
  const app = cloudbase.init(cloudbaseInitOptions(cloudbase));
  const collection = app.database().collection(REPORT_COLLECTION);
  return {
    async create(report) {
      try {
        await collection.add(report);
        return 'created';
      } catch (error) {
        if (isDuplicateError(error)) {
          return 'duplicate';
        }
        throw error;
      }
    },
    async list({ from, to, limit }) {
      const reports = [];
      const pageSize = 100;
      let offset = 0;
      while (reports.length <= limit) {
        const result = await collection
          .orderBy('received_at', 'asc')
          .skip(offset)
          .limit(pageSize)
          .get();
        const page = Array.isArray(result.data) ? result.data : [];
        if (page.length === 0) break;
        for (const report of page) {
          const day = String(report.received_at || '').slice(0, 10);
          if ((!from || day >= from) && (!to || day <= to)) {
            reports.push(report);
          }
        }
        offset += page.length;
        if (page.length < pageSize) break;
      }
      return {
        reports: reports.slice(0, limit),
        truncated: reports.length > limit,
      };
    },
  };
}

exports.handleRequest = handleRequest;
exports.sanitizeReport = sanitizeReport;
exports.reportsToCsv = reportsToCsv;
exports.cloudbaseInitOptions = cloudbaseInitOptions;

exports.main = async (event) => {
  try {
    return await handleRequest(event, {
      repository: createCloudRepository(),
      adminToken: process.env.BALANCE_TELEMETRY_ADMIN_TOKEN || '',
    });
  } catch (error) {
    console.error('balance telemetry request failed:', error?.message || 'unknown error');
    return response(500, { error: 'internal server error' });
  }
};
