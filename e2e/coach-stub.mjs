// Local stub for the coach service: canned replies for the Coach E2E flow. Never calls a model.
import http from 'node:http';

const port = Number(process.env.COACH_STUB_PORT ?? 8799);

function reply(res, status, body) {
  res.writeHead(status, { 'content-type': 'application/json' });
  res.end(JSON.stringify(body));
}

const server = http.createServer((req, res) => {
  if (req.method === 'GET' && req.url === '/health') {
    return reply(res, 200, { ok: true });
  }
  if (req.method === 'POST' && req.url === '/coach') {
    let raw = '';
    req.on('data', (chunk) => {
      raw += chunk;
    });
    req.on('end', () => {
      let question = '';
      try {
        question = String(JSON.parse(raw).question ?? '');
      } catch {
        return reply(res, 400, { error: 'bad json' });
      }
      console.log(`coach-stub: ${question}`);
      if (/3 days/i.test(question)) {
        return reply(res, 200, {
          answer: "Here's the change. Your finished workouts stay as they are.",
          citations: [],
          action: { type: 'adjustPlan', daysPerWeek: 3, sessionMinutes: 45 },
        });
      }
      if (/swap/i.test(question)) {
        return reply(res, 200, {
          answer: 'This keeps the same back work with less load on your lower back.',
          citations: [],
          action: {
            type: 'swap',
            from: process.env.COACH_STUB_SWAP_FROM ?? 'bent_row',
            to: process.env.COACH_STUB_SWAP_TO ?? 'seal_row',
          },
        });
      }
      return reply(res, 200, { answer: 'Rest a few minutes between heavy sets.', citations: [] });
    });
    return;
  }
  console.log(`coach-stub: 404 ${req.method} ${req.url}`);
  return reply(res, 404, { error: 'not found' });
});

server.listen(port, '127.0.0.1', () => {
  console.log(`coach-stub listening on http://127.0.0.1:${port}`);
});

for (const signal of ['SIGINT', 'SIGTERM']) {
  process.on(signal, () => server.close(() => process.exit(0)));
}
