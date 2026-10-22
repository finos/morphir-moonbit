// Imperative UI boundary. Identity text locates DATA in the genuine DOM;
// OwnedOpening retains the nominal objects and decides actual acceptance.
export type ConnectedChoice = Readonly<{kind: 'source'; providerId: string; locator: string}>
  | Readonly<{kind: 'project'; projectId: string}>;
export type ChoiceDocument = Pick<Document, 'querySelectorAll'>;
export function clickConnectedChoice(root: ChoiceDocument, choice: ConnectedChoice, actualIndex: number): 'clicked' | 'unavailable' {
  const buttons = Array.from(root.querySelectorAll<HTMLButtonElement>(choice.kind === 'source'
    ? 'button[data-model-source-provider][data-model-source-locator]' : 'button[data-model-project-id]'));
  const matches = buttons.filter(button => choice.kind === 'source'
    ? button.getAttribute('data-model-source-provider') === choice.providerId && button.getAttribute('data-model-source-locator') === choice.locator
    : button.getAttribute('data-model-project-id') === choice.projectId);
  const button = matches[0];
  if (matches.length !== 1 || button !== buttons[actualIndex] || !button?.isConnected || button.disabled) return 'unavailable';
  button.click();
  return 'clicked';
}
