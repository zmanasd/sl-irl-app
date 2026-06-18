import { randomUUID } from "node:crypto";

const DEFAULT_QUEUE_NAME = "relay:delivery";

export class MemoryDeliveryQueue {
  constructor({ name = DEFAULT_QUEUE_NAME } = {}) {
    this.name = name;
    this.jobs = [];
    this.waiters = [];
  }

  async enqueue(job) {
    const queuedJob = normalizeJob(job);
    this.jobs.push(queuedJob);
    const waiter = this.waiters.shift();
    if (waiter) waiter();
    return queuedJob;
  }

  async next({ timeoutMs = 0 } = {}) {
    if (this.jobs.length > 0) {
      return this.jobs.shift();
    }

    if (timeoutMs <= 0) return null;

    await new Promise((resolve) => {
      const timer = setTimeout(resolve, timeoutMs);
      this.waiters.push(() => {
        clearTimeout(timer);
        resolve();
      });
    });

    return this.jobs.shift() ?? null;
  }

  async length() {
    return this.jobs.length;
  }

  diagnostics() {
    return {
      type: "memory",
      name: this.name,
      pending: this.jobs.length
    };
  }

  async close() {}
}

export class RedisDeliveryQueue {
  constructor({ redis, name = DEFAULT_QUEUE_NAME }) {
    this.redis = redis;
    this.name = name;
  }

  static async create({
    url = process.env.REDIS_URL,
    name = process.env.RELAY_DELIVERY_QUEUE_NAME ?? DEFAULT_QUEUE_NAME
  } = {}) {
    if (!url) {
      throw new Error("REDIS_URL is required for Redis delivery queue.");
    }
    const { default: Redis } = await import("ioredis");
    const redis = new Redis(url, {
      maxRetriesPerRequest: 3,
      enableReadyCheck: true
    });
    return new RedisDeliveryQueue({ redis, name });
  }

  async enqueue(job) {
    const queuedJob = normalizeJob(job);
    await this.redis.lpush(this.name, JSON.stringify(queuedJob));
    return queuedJob;
  }

  async next({ timeoutMs = 0 } = {}) {
    if (timeoutMs > 0) {
      const timeoutSeconds = Math.max(1, Math.ceil(timeoutMs / 1000));
      const result = await this.redis.brpop(this.name, timeoutSeconds);
      return result?.[1] ? JSON.parse(result[1]) : null;
    }

    const raw = await this.redis.rpop(this.name);
    return raw ? JSON.parse(raw) : null;
  }

  async length() {
    return this.redis.llen(this.name);
  }

  async diagnostics() {
    return {
      type: "redis",
      name: this.name,
      pending: await this.length()
    };
  }

  async close() {
    await this.redis.quit();
  }
}

export async function createDeliveryQueueFromEnv(env = process.env) {
  const driver = env.RELAY_QUEUE_DRIVER ?? (env.REDIS_URL ? "redis" : "memory");

  if (driver === "redis") {
    return RedisDeliveryQueue.create({
      url: env.REDIS_URL,
      name: env.RELAY_DELIVERY_QUEUE_NAME ?? DEFAULT_QUEUE_NAME
    });
  }

  if (driver !== "memory") {
    throw new Error(`Unsupported RELAY_QUEUE_DRIVER: ${driver}`);
  }

  return new MemoryDeliveryQueue({
    name: env.RELAY_DELIVERY_QUEUE_NAME ?? DEFAULT_QUEUE_NAME
  });
}

function normalizeJob(job) {
  if (!job?.userId || !job?.alert) {
    throw new Error("Delivery queue jobs require userId and alert.");
  }

  return {
    id: job.id ?? `job_${randomUUID()}`,
    userId: job.userId,
    alert: job.alert,
    attempts: Number(job.attempts ?? 0),
    createdAt: job.createdAt ?? new Date().toISOString()
  };
}
