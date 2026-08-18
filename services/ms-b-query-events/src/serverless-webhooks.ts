import { deliverOneWebhook, materializeWebhookDeliveries } from './webhooks.ts';

export async function drainWebhookQueue(maxDeliveries = 5) {
  const materialized = await materializeWebhookDeliveries(Math.max(25, maxDeliveries * 20));
  let delivered = 0;
  for (let index = 0; index < maxDeliveries; index += 1) {
    if (!(await deliverOneWebhook())) break;
    delivered += 1;
  }
  return { materialized, delivered };
}
