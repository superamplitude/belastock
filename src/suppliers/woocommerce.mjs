export class WooCommerceAdapter {
  constructor(config) { this.config = config; }
  normalizeProduct(product) {
    return {
      sourceType: 'woocommerce',
      externalId: String(product.id),
      externalSku: product.sku || null,
      name: product.name || '',
      type: product.type || 'simple',
      status: product.status || 'draft',
      currentPrice: product.price === '' || product.price == null ? null : Number(product.price),
      stockQuantity: product.stock_quantity == null ? null : Number(product.stock_quantity),
      images: Array.isArray(product.images) ? product.images : [],
      attributes: Array.isArray(product.attributes) ? product.attributes : []
    };
  }
}
