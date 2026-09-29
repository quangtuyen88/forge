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
      let contract = null;
      let context = '';
      try {
        const parsed = JSON.parse(raw);
        question = String(parsed.question ?? '');
        contract = parsed.contract ?? null;
        if (typeof parsed.context === 'string') {
          context = parsed.context;
        }
      } catch {
        return reply(res, 400, { error: 'bad json' });
      }
      console.log(`coach-stub: ${question}`);
      if (contract && typeof contract === 'object') {
        console.log(`coach-stub: contract ${contract.proposal?.status ?? 'none'}`);
      } else {
        console.log('coach-stub: no contract');
      }
      if (context.includes('scope: one workout only')) {
        const otherWorkout = /(^|\n)(this_week|last_week|per_lift_bests|last_sets|planned_this_week|next_session):/.test(context)
          || (context.includes('Barbell Bench') && context.includes('Back Squat'));
        const health = /(^|\n)(sleep_hours|hrv_ms|resting_hr):/.test(context);
        const notes = /(^|\n)coach_notes:/.test(context);
        console.log(
          `coach-stub: scoped context=yes other_workout=${otherWorkout ? 'yes' : 'no'} health=${health ? 'yes' : 'no'} notes=${notes ? 'yes' : 'no'}`
        );
      }
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
      if (/roadmap|week 3|tuần 3/i.test(question)) {
        return reply(res, 200, {
          answer:
            'Your program week counts completed workouts: with 4 workouts a week, workouts 9 to 12 belong to week 3.',
          citations: [],
          action: null,
          sources: [{ id: 'program.week', title: 'How program weeks work', version: 'kb1', locale: 'en' }],
        });
      }
      if (/tomorrow/i.test(question)) {
        return reply(res, 200, { answer: 'Tomorrow is Lower, as planned.', citations: [], action: null });
      }
      const howDid = question.match(/how did my (.+?) go\??$/i);
      if (howDid) {
        return reply(res, 200, {
          answer: `Your ${howDid[1]} held steady across every set.`,
          citations: [],
          action: null,
        });
      }
      if (/best today/i.test(question)) {
        return reply(res, 200, {
          answer: 'Your back squat held steady across every set.',
          citations: [],
          action: null,
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
