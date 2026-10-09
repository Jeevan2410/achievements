// How a server answers parameterised statements on the prepared protocol, and whether
// the provider's client-side literal round-trips through an UPDATE.
import mysql from "mysql2/promise";

const conn = await mysql.createConnection({
  host: "127.0.0.1",
  port: Number(process.env.DB_PORT),
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD || undefined,
  database: "demo",
});
const show = (label, value) => console.log(`${label}: ${JSON.stringify(value)}`);
const attempt = async (label, fn) => {
  try {
    const [rows] = await fn();
    show(label, Array.isArray(rows) ? rows : { affectedRows: rows.affectedRows });
  } catch (e) {
    show(label, { errno: e.errno, code: e.code, sqlState: e.sqlState, fatal: e.fatal, message: e.message });
  }
};
const n = async () => (await conn.query("SELECT n, name FROM pk WHERE id = 1"))[0][0];

show("version", (await conn.query("SELECT VERSION() AS v"))[0][0]);
show("before", await n());
await attempt("execute SELECT ?", () => conn.execute("SELECT ? AS x", [1]));
await attempt("execute UPDATE n = n + 1", () => conn.execute("UPDATE pk SET n = n + 1 WHERE id = ?", [1]));
show("after refused UPDATE", await n());
await attempt("execute UPDATE name", () => conn.execute("UPDATE pk SET name = ? WHERE id = ?", ["x", 1]));
await attempt("execute INSERT", () => conn.execute("INSERT INTO pk (id, name, n) VALUES (?, ?, ?)", [9, "nine", 0]));
await attempt("execute DELETE", () => conn.execute("DELETE FROM pk WHERE id = ?", [9]));
try {
  const st = await conn.prepare("UPDATE pk SET n = n + 1 WHERE id = ?");
  show("prepare UPDATE", "prepared");
  await st.close();
} catch (e) {
  show("prepare UPDATE", { errno: e.errno, code: e.code, message: e.message });
}
show("after prepare only", await n());
// The provider's stringLiteral(): a quote doubled, a backslash escaped.
const literal = (v) => `'${v.replace(/\/g, "\\\\").replace(/'/g, "''")}'`;
const value = "\0\b\t\n\r\x1a\"'\ probe it's a \"quote\" \path";
await attempt("text SELECT literal", () => conn.query(`SELECT ${literal(value)} AS bound`));
const [sel] = await conn.query(`SELECT ${literal(value)} AS bound`);
show("SELECT literal round-trips", sel[0].bound === value);
await attempt("text UPDATE literal", () => conn.query(`UPDATE pk SET name = ${literal(value)}, n = n + 1 WHERE id = 1`));
const after = await n();
show("UPDATE literal round-trips", after.name === value);
show("after text UPDATE", { n: after.n });
await conn.end();
