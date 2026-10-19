import type { ButtonHTMLAttributes, ReactNode } from 'react';
import { ArrowRight, Crosshair, type LucideIcon } from 'lucide-react';

export function Button({ children, variant = 'primary', className = '', ...props }: ButtonHTMLAttributes<HTMLButtonElement> & { variant?: 'primary' | 'secondary' | 'ghost' | 'danger'; children: ReactNode }) {
  return <button className={`button button--${variant} ${className}`} {...props}>{children}</button>;
}
export function Badge({ children, tone = 'neutral', dot = false }: { children: ReactNode; tone?: 'neutral' | 'green' | 'amber' | 'blue'; dot?: boolean }) {
  return <span className={`badge badge--${tone}`}>{dot && <span className="status-dot"/>}{children}</span>;
}
export function PageTitle({ eyebrow, title, description, actions }: { eyebrow?: string; title: string; description: string; actions?: ReactNode }) {
  return <header className="page-title"><div>{eyebrow && <p className="eyebrow">{eyebrow}</p>}<h1>{title}</h1><p className="page-description">{description}</p></div>{actions && <div className="page-actions">{actions}</div>}</header>;
}
export function SectionHeading({ title, subtitle, action }: { title: string; subtitle?: string; action?: ReactNode }) {
  return <div className="section-heading"><div><h2>{title}</h2>{subtitle && <p>{subtitle}</p>}</div>{action}</div>;
}
export function EmptyState({ icon: Icon = Crosshair, title, description, action, compact = false }: { icon?: LucideIcon; title: string; description: string; action?: ReactNode; compact?: boolean }) {
  return <div className={`empty-state ${compact ? 'empty-state--compact' : ''}`}><span className="empty-icon"><Icon size={23} strokeWidth={1.5}/></span><h3>{title}</h3><p>{description}</p>{action}</div>;
}
export function TextLink({ children, onClick }: { children: ReactNode; onClick: () => void }) {
  return <button className="text-link" onClick={onClick}>{children}<ArrowRight size={15}/></button>;
}
export function DifficultyDots({ value, label = true }: { value: number; label?: boolean }) {
  return <span className="difficulty" aria-label={`Difficulty ${value} of 5`}><span className="difficulty-bars" aria-hidden="true">{[1, 2, 3, 4, 5].map(n => <i key={n} className={n <= value ? 'filled' : ''}/>)}</span>{label && <span>Level {value}</span>}</span>;
}
export function Field({ label, hint, children, htmlFor }: { label: string; hint?: string; children: ReactNode; htmlFor?: string }) {
  return <div className="field"><label htmlFor={htmlFor}>{label}</label>{children}{hint && <p className="field-hint">{hint}</p>}</div>;
}
export function Logo({ compact = false }: { compact?: boolean }) {
  return <div className={`brand ${compact ? 'brand--compact' : ''}`}><svg width="36" height="36" viewBox="0 0 44 44" fill="none" aria-hidden="true"><path d="M9 17V9h8m10 0h8v8m0 10v8h-8m-10 0H9v-8" stroke="currentColor" strokeWidth="2.4"/><path d="m15 21 5 6L30 14" stroke="currentColor" strokeWidth="2.4"/></svg><div><span className="brand-word">VIGIL<span className="brand-period">.</span></span>{!compact && <span className="brand-caption">SIMULATION & TRAINING</span>}</div></div>;
}
