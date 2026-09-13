import test from 'node:test';
import assert from 'node:assert/strict';
import { canTransitionOrder,canTransitionPrint,computeOrderTotals,normalizeQuantity,sanitizeCode } from '../src/commerce/core-math.mjs';

test('order totals are deterministic and rounded',()=>{
  assert.deepEqual(computeOrderTotals([{unitPrice:19.99,quantity:2},{unitPrice:10,quantity:1}],15,5),{subtotal:49.98,shippingTotal:15,discountTotal:5,grandTotal:59.98});
});

test('order workflow rejects invalid jumps',()=>{
  assert.equal(canTransitionOrder('pending','paid'),true);
  assert.equal(canTransitionOrder('pending','fulfilled'),false);
  assert.equal(canTransitionOrder('processing','fulfilled'),true);
});

test('print workflow follows library queue processed published contract',()=>{
  assert.equal(canTransitionPrint('library','queue'),true);
  assert.equal(canTransitionPrint('queue','published'),false);
  assert.equal(canTransitionPrint('queue','processed'),true);
  assert.equal(canTransitionPrint('processed','published'),true);
});

test('positioning code is normalized once and quantity is bounded',()=>{
  assert.equal(sanitizeCode(' frente camiseta 01 '),'FRENTE-CAMISETA-01');
  assert.equal(normalizeQuantity('3'),3);
  assert.throws(()=>normalizeQuantity(0));
  assert.throws(()=>normalizeQuantity(100));
});
