/**
 * 订单金额计算规则。
 * 保持为纯函数，便于首页结算和 Local Test 复用。
 */
export function calculatePayAmount(goodsTotal: number, deliveryFee: number, discountAmount: number): number {
  const safeGoodsTotal: number = Number.isFinite(goodsTotal) && goodsTotal > 0 ? goodsTotal : 0
  const safeDeliveryFee: number = Number.isFinite(deliveryFee) && deliveryFee > 0 ? deliveryFee : 0
  const safeDiscount: number = Number.isFinite(discountAmount) && discountAmount > 0 ? discountAmount : 0
  const payAmount: number = safeGoodsTotal + safeDeliveryFee - safeDiscount
  return payAmount > 0 ? Number(payAmount.toFixed(2)) : 0
}

export function calculateGoodsTotal(prices: number[], quantities: number[]): number {
  let total: number = 0
  const count: number = Math.min(prices.length, quantities.length)
  for (let i = 0; i < count; i++) {
    const price: number = Number.isFinite(prices[i]) && prices[i] > 0 ? prices[i] : 0
    const quantity: number = Number.isFinite(quantities[i]) && quantities[i] > 0 ? Math.floor(quantities[i]) : 0
    total += price * quantity
  }
  return Number(total.toFixed(2))
}
