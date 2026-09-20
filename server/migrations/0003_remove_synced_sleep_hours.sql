-- Forge worker schema v3 (D1). Apply: npx wrangler d1 migrations apply forge
--
-- Health-data correction. Earlier builds uploaded a check-in's `sleepHours`, which can be
-- HealthKit-derived; health metrics must stay on the device and never travel through sync.
-- This strips the key from every stored check-in record.
--
-- Only the objective `sleepHours` key is removed. The lifter's subjective scores — sleep
-- quality, soreness, energy, motivation and sore muscles — are untouched, and a record that
-- already lacks the key is not rewritten (`json_type` is NULL for a missing path, so such
-- rows fall out of the WHERE clause).
UPDATE records
SET data = json_remove(data, '$.sleepHours')
WHERE type = 'checkin'
  AND json_valid(data)
  AND json_type(data, '$.sleepHours') IS NOT NULL;
