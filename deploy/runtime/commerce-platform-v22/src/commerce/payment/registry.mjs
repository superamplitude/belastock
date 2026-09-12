export const PAYMENT_GATEWAYS = Object.freeze([
  { provider:'mercadopago', label:'Mercado Pago', capabilities:['pix','credit_card','debit_card','hosted_checkout'], implementation:'connector' },
  { provider:'pagbank', label:'PagBank', capabilities:['pix','credit_card','debit_card','boleto'], implementation:'connector' },
  { provider:'pagarme', label:'Pagar.me', capabilities:['pix','credit_card','boleto'], implementation:'connector' },
  { provider:'stripe', label:'Stripe', capabilities:['credit_card','wallet','hosted_checkout'], implementation:'connector' },
  { provider:'manual_pix', label:'PIX manual', capabilities:['pix'], implementation:'native' }
]);

export function listPaymentProviders() {
  return PAYMENT_GATEWAYS.map(provider => ({ ...provider }));
}

export function getPaymentProvider(provider) {
  const found = PAYMENT_GATEWAYS.find(item => item.provider === provider);
  if (!found) throw new Error(`Unsupported payment provider: ${provider}`);
  return found;
}
