// Validated application coordinates only. This value grants no source,
// registry, transport or controller authority.
export type ConnectedOpeningCoordinates = Readonly<{workspace: string; opening: number; attempt: string}>;

function snapshot(value: ConnectedOpeningCoordinates): ConnectedOpeningCoordinates {
  if (typeof value !== 'object' || value === null || Array.isArray(value)) throw new Error('Invalid connected opening coordinates.');
  const keys = Object.keys(value);
  if (keys.length !== 3 || !keys.includes('workspace') || !keys.includes('opening') || !keys.includes('attempt')) {
    throw new Error('Invalid connected opening coordinates.');
  }
  const workspace = value.workspace, opening = value.opening, attempt = value.attempt;
  // Match WorkspaceId::parse/render in workspace/workspace.mbt: w followed
  // by one to eight decimal digits, with no leading zero.
  if (typeof workspace !== 'string' || !/^w[1-9][0-9]{0,7}$/.test(workspace) ||
      !Number.isInteger(opening) || opening < 0 || opening > 2147483647 || Object.is(opening, -0) ||
      typeof attempt !== 'string' || !/^[1-9][0-9]{0,9}$/.test(attempt) || Number(attempt) > 2147483647) {
    throw new Error('Invalid connected opening coordinates.');
  }
  return Object.freeze({workspace, opening, attempt});
}

let read: (value: ConnectedOpeningContext) => ConnectedOpeningCoordinates;
export class ConnectedOpeningContext {
  readonly #coordinates: ConnectedOpeningCoordinates;
  private constructor(value: ConnectedOpeningCoordinates) {
    this.#coordinates = snapshot(value); Object.freeze(this);
  }
  static create(value: ConnectedOpeningCoordinates): ConnectedOpeningContext {return new ConnectedOpeningContext(value);}
  static {read = value => value.#coordinates;}
}

// Captures the private-field reader rather than dispatching through a caller's
// prototype or replaceable method. Forged and proxy owners fail the brand check.
export function readConnectedOpeningContext(value: ConnectedOpeningContext): ConnectedOpeningCoordinates {return read(value);}
