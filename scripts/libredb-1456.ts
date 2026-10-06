// Seeds a real MongoDB and prints what libredb's MongoDB provider infers (#1456).
import { MongoClient } from "mongodb";
import { MongoDBProvider } from "@/lib/db/providers/document/mongodb";

const client = new MongoClient("mongodb://localhost:27017");
await client.connect();
const db = client.db("checkdb");
await db.dropDatabase();
await db.collection("things").insertMany([
  { name: "Ada", city: "Istanbul", nick: null, address: { city: "Izmir", zip: "35000" } },
  { name: "Grace", city: "Ankara", address: { city: "Ankara" } },
  { name: "Lin" },
]);
const version = (await db.admin().command({ buildInfo: 1 })).version;
await client.close();

const provider = new MongoDBProvider({
  id: "check", name: "check", type: "mongodb", host: "localhost", port: 27017, database: "checkdb", createdAt: new Date(),
} as never);
await provider.connect();
const detail = await provider.describeObject(["checkdb", "things"], "collection");
console.log(`MongoDB ${version}`);
console.table(detail.columns.map((c) => ({ name: c.name, type: c.type, nullable: c.nullable })));
await provider.disconnect();
