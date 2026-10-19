import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { describe, expect, it, vi } from 'vitest';
import { ConfirmDialog } from './ConfirmDialog';

describe('destructive exercise confirmation', () => {
  it('initially focuses Cancel and contains keyboard focus', async () => {
    const user = userEvent.setup(); render(<ConfirmDialog title="Reset this exercise?" description="The active log will be discarded." confirmLabel="Discard & reset" onCancel={() => {}} onConfirm={() => {}}/>);
    const cancel = screen.getByRole('button', { name: 'Cancel' }); const confirm = screen.getByRole('button', { name: 'Discard & reset' });
    expect(cancel).toHaveFocus(); await user.tab(); expect(confirm).toHaveFocus(); await user.tab(); expect(cancel).toHaveFocus(); await user.tab({ shift: true }); expect(confirm).toHaveFocus();
  });
  it('Escape cancels and never confirms a destructive transition', async () => {
    const user = userEvent.setup(); const cancel = vi.fn(); const confirm = vi.fn();
    render(<ConfirmDialog title="End early?" description="Only a partial result is available." confirmLabel="End exercise" onCancel={cancel} onConfirm={confirm}/>);
    await user.keyboard('{Escape}'); expect(cancel).toHaveBeenCalledOnce(); expect(confirm).not.toHaveBeenCalled();
  });
  it('requires an explicit confirmation click', async () => {
    const user = userEvent.setup(); const cancel = vi.fn(); const confirm = vi.fn();
    render(<ConfirmDialog title="Reset?" description="Discard this attempt." confirmLabel="Discard & reset" onCancel={cancel} onConfirm={confirm}/>);
    await user.click(screen.getByRole('button', { name: 'Discard & reset' })); expect(confirm).toHaveBeenCalledOnce(); expect(cancel).not.toHaveBeenCalled();
  });
});
