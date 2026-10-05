// Measures which maintenance commands a real MongoDB accepts per collection type.
// Used to verify libredb/libredb-studio#1522 (issue #1408). Read-only for anything
// outside the throwaway "checkdb" database it creates.
import { MongoClient } from "mongodb";

const client = new MongoClient(process.env.MONGO_URL ?? "mongodb://localhost:27017", {
  serverSelectionTimeoutMS: 10000,
});
await client.connect();
const db = client.db("checkdb");
await db.dropDatabase();

await db.collection("users").insertMany([{ name: "a", active: true }, { name: "b", active: false }]);
await db.createCollection("active_users", { viewOn: "users", pipeline: [{ $match: { active: true } }] });
await db.createCollection("readings", { timeseries: { timeField: "ts", metaField: "sensor" } });
await db.collection("readings").insertMany([
  { ts: new Date(), sensor: "s1", v: 1 },
  { ts: new Date(), sensor: "s2", v: 2 },
]);

const version = (await db.admin().command({ buildInfo: 1 })).version;
const infos = await db.listCollections().toArray();
const rows = [];
for (const info of infos) {
  for (const command of ["validate", "compact"]) {
    try {
      const res = await db.command({ [command]: info.name });
      rows.push({ name: info.name, type: info.type, command, ok: res.ok, valid: res.valid });
    } catch (error) {
      rows.push({ name: info.name, type: info.type, command, error: `${error.code} ${error.codeName}: ${error.message}` });
    }
  }
}
console.log(`MongoDB ${version}`);
console.table(rows);
await client.close();
