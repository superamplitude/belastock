import test from 'node:test';
import assert from 'node:assert/strict';
import { listPaymentProviders, getPaymentProvider } from '../src/commerce/payment/registry.mjs';
import { listShippingProviders, getShippingProvider } from '../src/commerce/shipping/registry.mjs';

test('payment registry exposes multiple gateways and native PIX', () => {
  const providers = listPaymentProviders();
  assert.ok(providers.length >= 5);
  assert.equal(getPaymentProvider('mercadopago').label, 'Mercado Pago');
  assert.equal(getPaymentProvider('manual_pix').implementation, 'native');
});

test('shipping registry supports carrier-required and supplier fulfillment flows', () => {
  const providers = listShippingProviders();
  assert.ok(providers.some(p => p.provider === 'correios'));
  assert.ok(providers.some(p => p.provider === 'melhor_envio'));
  assert.equal(getShippingProvider('custom').implementation, 'native');
  assert.ok(getShippingProvider('supplier').capabilities.includes('supplier_fulfillment'));
});
