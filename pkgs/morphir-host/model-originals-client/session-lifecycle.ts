/** Attempt-bound synchronous observation of actual business port invocations. These are
 * producer interfaces, not effect records, verdicts or source authority. */
export type ModelOriginalsExchangeStart = Readonly<{
  method: 'morphir.session.initialize' | 'morphir.workspace.open' |
    `morphir.model-originals.${'capture' | 'inventory' | 'read' | 'release'}`;
  requestId: string;
  request: string;
}>;
export type ModelOriginalsExchangeResponse = Readonly<{kind: 'not-returned'}> | Readonly<{kind: 'returned'; reply: string}>;
export type ModelOriginalsManifestResponse = Readonly<{kind: 'not-received'}> | Readonly<{
  kind: 'received'; body: Readonly<{kind: 'not-complete'}> | Readonly<{kind: 'complete'; raw: string}>;
}>;
export interface ModelOriginalsManifestPort {
  resolved(value: Readonly<{raw: string; outcome: 'offered' | 'not-offered'}>): void;
  rejected(value: Readonly<{cause: unknown; response: ModelOriginalsManifestResponse}>): void;
}
export interface ModelOriginalsExchangePort {
  resolved(value: Readonly<{reply: string}>): void;
  rejected(value: Readonly<{cause: unknown; response: ModelOriginalsExchangeResponse}>): void;
}
export interface ModelOriginalsLifecycleProducer {
  /** Pending registration is synchronous and precedes the actual port call. */
  beginManifest(request: Readonly<{url: string}>): ModelOriginalsManifestPort;
  beginExchange(request: ModelOriginalsExchangeStart): ModelOriginalsExchangePort;
  /** Observation failed. This must never be presented as a business rejection. */
  poisoned(cause: unknown): void;
}

type Port<Resolved extends object, Rejected extends object> = {
  resolved(value: Resolved): void;
  rejected(value: Rejected): void;
};
class ObservedPort<Resolved extends object, Rejected extends object> {
  #state: {kind: 'pending'; port: Port<Resolved, Rejected>} | {kind: 'terminal'};
  readonly #scope: SessionLifecycle;
  constructor(scope: SessionLifecycle, port: Port<Resolved, Rejected>) {
    if (port instanceof Promise) {
      void port.catch(() => {});
      throw new TypeError('Lifecycle begin must return a synchronous port observer.');
    }
    // Snapshot the actual observer's methods before the actual business effect.
    const resolved = port.resolved, rejected = port.rejected;
    if (typeof resolved !== 'function' || typeof rejected !== 'function') throw new TypeError('Invalid lifecycle port observer.');
    this.#state = {kind: 'pending', port: {
      resolved: value => resolved.call(port, value), rejected: value => rejected.call(port, value),
    }};
    this.#scope = scope;
  }
  resolved(value: Resolved): void {this.#finish(port => port.resolved(Object.freeze(value)));}
  rejected(value: Rejected): void {this.#finish(port => port.rejected(Object.freeze(value)));}
  #finish(invoke: (port: Port<Resolved, Rejected>) => void): void {
    const state = this.#state;
    if (state.kind !== 'pending') return;
    this.#state = {kind: 'terminal'};
    this.#scope.invoke(() => invoke(state.port));
  }
}

/** Internal nonraising bridge. A failed observer is never reused. The owning
 * producer must retain its own incomplete state; this is not a registry. */
export class SessionLifecycle {
  #state: 'active' | 'poisoned' = 'active';
  readonly #producer: ModelOriginalsLifecycleProducer;
  constructor(producer: ModelOriginalsLifecycleProducer) {this.#producer = producer;}
  #poison(cause: unknown): void {
    if (this.#state === 'poisoned') return;
    this.#state = 'poisoned';
    try {
      const returned: unknown = this.#producer.poisoned(cause);
      if (returned instanceof Promise) void returned.catch(() => {});
    } catch { /* Observation failure cannot replace business values or errors. */ }
  }
  invoke(invoke: () => void): void {
    if (this.#state !== 'active') return;
    try {
      const returned: unknown = invoke();
      if (returned instanceof Promise) {
        void returned.catch(() => {});
        this.#poison(new TypeError('Lifecycle terminal observers must complete synchronously.'));
      }
    } catch (cause) {this.#poison(cause);}
  }
  beginManifest(request: Readonly<{url: string}>): ObservedPort<Parameters<ModelOriginalsManifestPort['resolved']>[0], Parameters<ModelOriginalsManifestPort['rejected']>[0]> | undefined {
    if (this.#state !== 'active') return;
    try {return new ObservedPort(this, this.#producer.beginManifest(Object.freeze(request)));}
    catch (cause) {this.#poison(cause);}
  }
  beginExchange(request: ModelOriginalsExchangeStart): ObservedPort<Parameters<ModelOriginalsExchangePort['resolved']>[0], Parameters<ModelOriginalsExchangePort['rejected']>[0]> | undefined {
    if (this.#state !== 'active') return;
    try {return new ObservedPort(this, this.#producer.beginExchange(Object.freeze(request)));}
    catch (cause) {this.#poison(cause);}
  }
}
