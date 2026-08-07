export function problem(reply, status, code, title, detail, extra = {}) {
  return reply.code(status).type('application/problem+json').send({
    type: `urn:autorunner:problem:${code}`,
    title,
    status,
    code,
    detail,
    traceId: reply.request?.id,
    ...extra,
  });
}

export class DomainError extends Error {
  constructor(code, message, status = 400, meta = {}) {
    super(message);
    this.name = 'DomainError';
    this.code = code;
    this.status = status;
    this.meta = meta;
  }
}
