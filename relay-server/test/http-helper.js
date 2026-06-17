import { once } from "node:events";
import { createServer } from "node:http";

export async function withTestServer(app, fn) {
  const server = createServer(app);
  server.listen(0, "127.0.0.1");
  await once(server, "listening");
  const { port } = server.address();
  const baseUrl = `http://127.0.0.1:${port}`;

  try {
    return await fn(baseUrl);
  } finally {
    server.close();
    await once(server, "close");
  }
}
