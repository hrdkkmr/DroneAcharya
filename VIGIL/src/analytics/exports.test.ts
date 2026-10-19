import {describe,it,expect} from 'vitest';
import {csvCell,summaryCsv,backupJson,reportHtml,escapeHtml} from './exports';
import {INITIAL_PROFILES,parseBundle} from '../persistence/validation';
import {historyRecord} from '../test/historyFixtures';
describe('portable, spreadsheet and printable actual reports',()=>{
  it('exports round-trippable format1 JSON and no current synthetic history is inserted',()=>{expect(parseBundle(backupJson(INITIAL_PROFILES,[])).sessions).toEqual([]);const r=historyRecord();expect(parseBundle(backupJson(INITIAL_PROFILES,[r])).sessions[0]).toEqual(r);});
  it.each(['=HYPERLINK("evil")','+SUM(1,1)','-42','@cmd',' \t=evil','\ttext'])('neutralises spreadsheet formula prefix %s',value=>expect(csvCell(value)).toMatch(/^"'/));
  it('quotes commas/quotes/newlines according to RFC4180 and includes honest persistence/outcome columns',()=>{expect(csvCell('A,"B"\nC')).toBe('"A,""B""\nC"');const r=historyRecord('csv','aborted');const text=summaryCsv([r],[{...INITIAL_PROFILES[0],name:'=formula'}],new Set());expect(text).toContain('"\'=formula"');expect(text).toContain('"aborted","no","no"');expect(text.startsWith('\ufeff')).toBe(true);expect(text.endsWith('\r\n')).toBe(true);});
  it('escapes hostile profile/report text and retains actual score/order/event count in a self-contained HTML report',()=>{const r=historyRecord();const html=reportHtml(r,{...INITIAL_PROFILES[0],name:'<script>bad</script>'});expect(html).not.toContain('<script>bad');expect(html).toContain('&lt;script&gt;bad&lt;/script&gt;');expect(html).toContain(`${r.evaluation.score.toFixed(1)} / 100`);for(const event of r.events)expect(html).toContain(`id="event-${event.order}"`);expect(html).not.toMatch(/https?:\/\/|<link|<script src/);expect(html).toContain('not proof of authorship');});
  it('clearly marks aborted/no-evidence reports as noncomparable rather than a valid progress result',()=>{const html=reportHtml(historyRecord('abort','aborted'),INITIAL_PROFILES[0]);expect(html).toContain('Not comparable and excluded');expect(html).toContain('Original order is retained');expect(escapeHtml('"<&\'')).toBe('&quot;&lt;&amp;&#39;');});
});
