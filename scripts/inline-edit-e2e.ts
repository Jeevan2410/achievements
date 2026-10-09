// Runs the inline editor's two statements through the provider: the key check, then the UPDATE.
import { MySQLProvider } from "./src/lib/db/providers/sql/mysql";

const BS = String.fromCharCode(92);
const value = `it's a "quoted" ${BS}path`;
const provider = new MySQLProvider({
  id: "e2e",
  name: "e2e",
  type: "mysql",
  host: "127.0.0.1",
  port: Number(process.env.DB_PORT),
  database: "demo",
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD || undefined,
  createdAt: new Date(),
} as never);
await provider.connect();
const version = await provider
  .query("SELECT current_version() AS v")
  .catch(() => provider.query("SELECT VERSION() AS v"));
console.log(`version: ${JSON.stringify(version.rows[0])}`);
const read = async () => (await provider.query("SELECT `n`, `name` FROM `pk` WHERE `id` = 1")).rows[0] as Record<string, unknown>;
console.log(`before: ${JSON.stringify(await read())}`);
const keys = await provider.query("SELECT `id`, COUNT(*) AS `key_rows` FROM `pk` WHERE `id` IN (?) GROUP BY `id`", [1]);
console.log(`key check: ${JSON.stringify(keys.rows)}`);
try {
  const update = await provider.query("UPDATE `pk` SET `name` = ? WHERE `id` = ?", [value, 1]);
  console.log(`inline UPDATE: rowCount ${update.rowCount}`);
} catch (error) {
  console.log(`inline UPDATE failed: ${(error as Error).message}`);
}
try {
  await provider.query("UPDATE `pk` SET `n` = `n` + 1 WHERE `id` = ?", [1]);
  console.log("counter UPDATE: sent");
} catch (error) {
  console.log(`counter UPDATE failed: ${(error as Error).message}`);
}
const after = await read();
console.log(`after: n=${String(after.n)} name round-trips=${after.name === value} name=${JSON.stringify(after.name)}`);
await provider.disconnect();
