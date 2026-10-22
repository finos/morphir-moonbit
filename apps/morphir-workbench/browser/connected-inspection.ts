import type {ConnectedModelOpening, PendingOriginalInspection} from './connected-originals.ts';

export type ConnectedBoundary = 'inspection-pending' | 'opening-settled';
export type ConnectedBoundaryOutcome = Readonly<{kind:
  'inspection-pending' | 'originals-only' | 'stored' | 'retired' | 'failed' | 'no-opening' | 'replaced'}>;

/** One page's actual opening. Fixed driver controls accept no source, request,
 * module, expected result or producer-selected case identity. */
export class ConnectedInspectionControls {
  #mode: 'ordinary' | 'observed' | 'closed' = 'ordinary';
  #opening: ConnectedModelOpening | undefined;
  prepareObserved(): void {
    if (this.#opening || this.#mode === 'closed') throw new Error('Prepare observed inspection before opening a model.');
    this.#mode = 'observed';
  }
  register(opening: ConnectedModelOpening): void {
    if (this.#mode === 'closed') opening.dispose(); else this.#opening = opening;
  }
  revoke(): void {
    const opening = this.#opening;
    this.#mode = 'closed'; this.#opening = undefined;
    opening?.dispose();
  }
  unregister(opening: ConnectedModelOpening): void {if (this.#opening === opening) this.#opening = undefined;}
  hold(stage: PendingOriginalInspection, enqueue: () => void, cancel: () => void): 'held' | 'ignored' {
    const opening = this.#opening;
    if (!opening || opening.holdInspection(stage, enqueue, cancel) !== 'held') return 'ignored';
    if (this.#mode === 'ordinary') opening.currentPendingInspection?.executePendingCore();
    return 'held';
  }
  executePendingCore(): 'enqueued' | 'ignored' {
    return this.#opening?.currentPendingInspection?.executePendingCore() ?? 'ignored';
  }
  async awaitBoundary(boundary: ConnectedBoundary): Promise<ConnectedBoundaryOutcome> {
    if (boundary !== 'inspection-pending' && boundary !== 'opening-settled') throw new Error('Invalid connected boundary.');
    const opening = this.#opening;
    if (!opening) return Object.freeze({kind: this.#mode === 'closed' ? 'retired' : 'no-opening'});
    const outcome = await (boundary === 'inspection-pending' ? opening.whenInspectionPending() : opening.whenOpeningSettled());
    return Object.freeze({kind: this.#opening === opening ? outcome.kind : 'replaced'});
  }
}

// Build externalizes this one module for both ordinary bootstrap and the fixed
// observed entry, so holding and executing never consult different instances.
export const connectedInspection = new ConnectedInspectionControls();
