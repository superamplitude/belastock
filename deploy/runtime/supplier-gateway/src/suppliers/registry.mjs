import { WooCommerceAdapter } from './woocommerce.mjs';

export const SUPPLIER_ADAPTERS = Object.freeze([
  { type: 'woocommerce', label: 'WooCommerce REST API', implemented: true },
  { type: 'json', label: 'API / feed JSON', implemented: false },
  { type: 'xml', label: 'Feed XML', implemented: false },
  { type: 'csv', label: 'CSV / planilha', implemented: false },
  { type: 'manual', label: 'Cadastro manual', implemented: false }
]);

export function supportedSupplierAdapters() {
  return SUPPLIER_ADAPTERS.map(item => ({ ...item }));
}

export function buildSupplierAdapter(supplier, credentials = {}) {
  switch (supplier.adapter_type) {
    case 'woocommerce':
      return new WooCommerceAdapter({
        baseUrl: supplier.base_url,
        consumerKey: credentials.consumerKey,
        consumerSecret: credentials.consumerSecret,
        webhookSecret: credentials.webhookSecret || ''
      });
    default:
      throw new Error(`Supplier adapter not implemented: ${supplier.adapter_type}`);
  }
}
