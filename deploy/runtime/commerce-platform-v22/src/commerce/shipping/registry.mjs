export const SHIPPING_PROVIDERS = Object.freeze([
  { provider:'correios', label:'Correios', capabilities:['quote','tracking','label'], implementation:'connector' },
  { provider:'melhor_envio', label:'Melhor Envio', capabilities:['quote','tracking','label','multi_carrier'], implementation:'connector' },
  { provider:'frenet', label:'Frenet', capabilities:['quote','multi_carrier'], implementation:'connector' },
  { provider:'jadlog', label:'Jadlog', capabilities:['quote','tracking','label'], implementation:'connector' },
  { provider:'custom', label:'Transportadora própria / contratada', capabilities:['manual_quote','tracking'], implementation:'native' },
  { provider:'supplier', label:'Frete do próprio fornecedor', capabilities:['supplier_fulfillment'], implementation:'native' },
  { provider:'pickup', label:'Retirada no local', capabilities:['pickup'], implementation:'native' }
]);

export function listShippingProviders() {
  return SHIPPING_PROVIDERS.map(provider => ({ ...provider }));
}

export function getShippingProvider(provider) {
  const found = SHIPPING_PROVIDERS.find(item => item.provider === provider);
  if (!found) throw new Error(`Unsupported shipping provider: ${provider}`);
  return found;
}
