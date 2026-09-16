'use strict';

const assert = require('node:assert/strict');
const test = require('node:test');
const { cloudbaseInitOptions, eventsToCsv, handleRequest, reportsToCsv } = require('../index.js');

function validReport() {
  return {
    schema_version: 1,
    report_id: 'report_0123456789abcdef0123456789abcdef',
    anonymous_player_id: 'anon_0123456789abcdef0123456789abcdef',
    run_id: 'run_0123456789abcdef0123456789abcdef',
    game_version: '1.0.1',
    platform: 'Android',
    difficulty: 2,
    sect_id: 'HuaShanPai',
    final_score: 500,
    victory_count: 1,
    defeat_count: 0,
    formal_victory_count: 1,
    formal_defeat_count: 0,
    started_at: 100,
    completed_at: 200,
    duels: [{
      duel_index: 1,
      enemy_id: 'qingfeng_xuedi',
      player_level: 1,
      starting_owner: 1,
      outcome: 'victory',
      counts_for_progress: true,
      started_at: 110,
      completed_at: 120,
      player_card_ids: ['A', 'B', 'C', 'D', 'E'],
      enemy_card_ids: ['F', 'G', 'H', 'I', 'J'],
    }],
  };
}

function event(method, path, body = '', headers = {}) {
  return { httpMethod: method, path, body, headers };
}

function validPlayerEvent() {
  return {
    schema_version: 1,
    event_id: 'event_0123456789abcdef0123456789abcdef',
    anonymous_player_id: 'anon_0123456789abcdef0123456789abcdef',
    event_type: 'beginner_flow_completed',
    game_version: '1.0.2',
    platform: 'Android',
    occurred_at: 300,
  };
}

function repository(createResult = 'created', reports = []) {
	const createdReports = [];
	const createdEvents = [];
  return {
	created: createdReports,
	createdReports,
	createdEvents,
	async createReport(report) {
	  createdReports.push(report);
      return createResult;
    },
	async createEvent(playerEvent) {
	  createdEvents.push(playerEvent);
	  return createResult;
	},
	async listReports() {
      return { reports, truncated: false };
    },
	async listEvents() {
	  return { events: createdEvents, truncated: false };
	},
  };
}

test('stores one sanitized report and strips unknown fields', async () => {
  const repo = repository();
  const payload = validReport();
  payload.unknown = 'discard me';
  const result = await handleRequest(
    event('POST', '/v1/reports', JSON.stringify(payload), { 'content-type': 'application/json' }),
    { repository: repo, now: () => '2026-09-15T00:00:00.000Z' }
  );
  assert.equal(result.statusCode, 201);
  assert.equal(repo.created.length, 1);
  assert.equal(repo.created[0]._id, payload.report_id);
  assert.equal(repo.created[0].received_at, '2026-09-15T00:00:00.000Z');
  assert.equal(repo.created[0].unknown, undefined);
});

test('accepts the route after CloudBase strips the gateway prefix', async () => {
  const repo = repository();
  const result = await handleRequest(
    event('POST', '/reports', JSON.stringify(validReport()), { 'content-type': 'application/json' }),
    { repository: repo }
  );
  assert.equal(result.statusCode, 201);
  assert.equal(repo.created.length, 1);
});

test('duplicate report id returns idempotent success semantics', async () => {
  const result = await handleRequest(
    event('POST', '/v1/reports', JSON.stringify(validReport()), { 'content-type': 'application/json' }),
    { repository: repository('duplicate') }
  );
  assert.equal(result.statusCode, 409);
  assert.equal(JSON.parse(result.body).duplicate, true);
});

test('stores one strict lightweight event on either gateway route', async () => {
  const repo = repository();
  const payload = validPlayerEvent();
  const result = await handleRequest(
	event('POST', '/v1/events', JSON.stringify(payload), { 'content-type': 'application/json' }),
	{ repository: repo, now: () => '2026-09-16T00:00:00.000Z' }
  );
  assert.equal(result.statusCode, 201);
  assert.equal(repo.createdEvents.length, 1);
  assert.equal(repo.createdEvents[0]._id, payload.event_id);
  assert.equal(repo.createdEvents[0].received_at, '2026-09-16T00:00:00.000Z');
  const relative = await handleRequest(
	event('POST', '/events', JSON.stringify(payload), { 'content-type': 'application/json' }),
	{ repository: repository() }
  );
  assert.equal(relative.statusCode, 201);
});

test('rejects event extras and treats duplicate event ids idempotently', async () => {
  const repo = repository();
  const extra = { ...validPlayerEvent(), duels: [] };
  const rejected = await handleRequest(
	event('POST', '/v1/events', JSON.stringify(extra), { 'content-type': 'application/json' }),
	{ repository: repo }
  );
  assert.equal(rejected.statusCode, 400);
  assert.equal(repo.createdEvents.length, 0);
  const duplicate = await handleRequest(
	event('POST', '/v1/events', JSON.stringify(validPlayerEvent()), { 'content-type': 'application/json' }),
	{ repository: repository('duplicate') }
  );
  assert.equal(duplicate.statusCode, 409);
});

test('rejects malformed reports before database access', async () => {
  const repo = repository();
  const payload = validReport();
  payload.duels[0].player_card_ids.pop();
  const result = await handleRequest(
    event('POST', '/v1/reports', JSON.stringify(payload), { 'content-type': 'application/json' }),
    { repository: repo }
  );
  assert.equal(result.statusCode, 400);
  assert.equal(repo.created.length, 0);
});

test('rejects totals that disagree with duel outcomes', async () => {
  const payload = validReport();
  payload.defeat_count = 1;
  const result = await handleRequest(
    event('POST', '/v1/reports', JSON.stringify(payload), { 'content-type': 'application/json' }),
    { repository: repository() }
  );
  assert.equal(result.statusCode, 400);
});

test('admin export requires exact bearer token', async () => {
  const denied = await handleRequest(
    event('GET', '/v1/admin/export', '', {}),
    { repository: repository(), adminToken: 'secret' }
  );
  assert.equal(denied.statusCode, 401);
  const allowed = await handleRequest(
    { ...event('GET', '/v1/admin/export', '', { authorization: 'Bearer secret' }), queryStringParameters: { format: 'json' } },
    { repository: repository('created', [validReport()]), adminToken: 'secret' }
  );
  assert.equal(allowed.statusCode, 200);
  assert.equal(JSON.parse(allowed.body).reports.length, 1);

  const relative = await handleRequest(
    { ...event('GET', '/admin/export', '', { authorization: 'Bearer secret' }), queryStringParameters: { format: 'json' } },
    { repository: repository('created', [validReport()]), adminToken: 'secret' }
  );
  assert.equal(relative.statusCode, 200);
});

test('admin export selects the independent events dataset', async () => {
  const repo = repository();
  repo.createdEvents.push({ ...validPlayerEvent(), received_at: '2026-09-16T00:00:00.000Z' });
  const jsonResult = await handleRequest(
	{ ...event('GET', '/v1/admin/export', '', { authorization: 'Bearer secret' }), queryStringParameters: { format: 'json', dataset: 'events' } },
	{ repository: repo, adminToken: 'secret' }
  );
  assert.equal(jsonResult.statusCode, 200);
  assert.equal(JSON.parse(jsonResult.body).events.length, 1);
  const csvResult = await handleRequest(
	{ ...event('GET', '/v1/admin/export', '', { authorization: 'Bearer secret' }), queryStringParameters: { format: 'csv', dataset: 'events' } },
	{ repository: repo, adminToken: 'secret' }
  );
  assert.equal(csvResult.statusCode, 200);
  assert.ok(csvResult.body.includes('beginner_flow_completed'));
});

test('CSV uses one duel per row and escapes cells', () => {
  const payload = validReport();
  payload.sect_id = 'Hua,Shan';
  payload.received_at = '2026-09-15T00:00:00.000Z';
  const csv = reportsToCsv([payload]);
  assert.ok(csv.startsWith('\uFEFFreport_id,'));
  assert.ok(csv.includes('"Hua,Shan"'));
  assert.equal(csv.trim().split('\r\n').length, 2);
});

test('event CSV uses one count event per row', () => {
  const csv = eventsToCsv([{ ...validPlayerEvent(), received_at: '2026-09-16T00:00:00.000Z' }]);
  assert.ok(csv.startsWith('\uFEFFevent_id,'));
  assert.equal(csv.trim().split('\r\n').length, 2);
});

test('server database access uses the Cloud API endpoint mode', () => {
  const currentEnvironment = Symbol('current-environment');
  assert.deepEqual(
    cloudbaseInitOptions(
      { SYMBOL_CURRENT_ENV: currentEnvironment },
      {
        TENCENTCLOUD_SECRETID: 'temporary-id',
        TENCENTCLOUD_SECRETKEY: 'temporary-key',
        TENCENTCLOUD_SESSIONTOKEN: 'temporary-token',
      }
    ),
    {
      env: currentEnvironment,
      endPointMode: 'CLOUD_API',
      secretId: 'temporary-id',
      secretKey: 'temporary-key',
      sessionToken: 'temporary-token',
    }
  );
});
