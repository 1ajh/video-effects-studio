import fs from 'node:fs';
import path from 'node:path';

/**
 * Orders in one JSON file, written atomically (temp file + rename) and one
 * write at a time. Plenty for a store that sells by DM.
 */
export class Store {
  constructor(file) {
    this.file = file;
    this.data = { orders: [] };
    this.queue = Promise.resolve();
    if (fs.existsSync(file)) this.data = JSON.parse(fs.readFileSync(file, 'utf8'));
    this.data.orders ??= [];
  }

  get orders() {
    return this.data.orders;
  }

  byToken(token) {
    return this.orders.find((o) => o.token === token) ?? null;
  }

  byId(id) {
    return this.orders.find((o) => o.id === id) ?? null;
  }

  byCode(code) {
    return this.orders.find((o) => o.code === code) ?? null;
  }

  byKey(key) {
    return this.orders.find((o) => o.licenseKey === key) ?? null;
  }

  add(order) {
    this.orders.push(order);
    return this.save();
  }

  /** Writes the file; resolves when this change is on disk. */
  save() {
    const snapshot = JSON.stringify(this.data, null, 1);
    this.queue = this.queue.then(async () => {
      await fs.promises.mkdir(path.dirname(this.file), { recursive: true });
      const tmp = `${this.file}.${process.pid}.tmp`;
      await fs.promises.writeFile(tmp, snapshot, { mode: 0o600 });
      await fs.promises.rename(tmp, this.file);
    });
    return this.queue;
  }
}
