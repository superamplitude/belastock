import test from 'node:test';
import assert from 'node:assert/strict';
import { buildPreviewItem, normalizeImportProfile } from '../src/services/supplier-preview.mjs';

test('supplier preview calculates suggested selling price without importing', () => {
  const preview = buildPreviewItem({
    externalId:'10', externalSku:'ABC', name:'Camiseta', type:'simple', status:'publish',
    currentPrice:60, stockQuantity:10, stockStatus:'instock', images:[{src:'https://example.test/a.jpg'}], categories:[], attributes:[]
  }, { target_margin_pct:40, fixed_overhead:0, minimum_stock:2 });
  assert.equal(preview.sourceCost, 60);
  assert.equal(preview.suggestedPrice, 100);
  assert.equal(preview.eligible, true);
});

test('supplier preview blocks item below configured minimum stock', () => {
  const preview = buildPreviewItem({
    externalId:'11', externalSku:'LOW', name:'Baixo estoque', type:'simple', status:'publish',
    currentPrice:20, stockQuantity:1, stockStatus:'instock', images:[], categories:[], attributes:[]
  }, { minimum_stock:2 });
  assert.equal(preview.eligible, false);
  assert.ok(preview.issues.some(issue => issue.code === 'below_minimum_stock'));
});

test('profile normalization keeps test mode as safe default', () => {
  const profile = normalizeImportProfile({});
  assert.equal(profile.mode, 'test');
  assert.equal(profile.autoPromote, false);
  assert.equal(profile.previewLimit, 20);
});
