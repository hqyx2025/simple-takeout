import { Coupon } from '../model/Models'

/** 金额来自服务端 DECIMAL(…, 2)，以分比较，避免 0.1 + 0.2 的浮点误差。 */
export function checkoutCents(value: number): number {
  if (!Number.isFinite(value)) { return Number.NaN }
  const parts: string[] = value.toString().split('e')
  const exponent: number = parts.length > 1 ? Number(parts[1]) : 0
  return Math.round(Number(`${parts[0]}e${exponent + 2}`))
}

/** 空字符串表示可用。门槛只含商品，券后实付包含配送费，均与下单规则一致。 */
export function checkoutCouponReason(coupon: Coupon, storeId: number, goodsAmount: number,
  deliveryFee: number, now: number, rejectedCouponId: number = 0): string {
  if (coupon.id <= 0 || !Number.isFinite(coupon.amount) || coupon.amount <= 0
    || !Number.isFinite(coupon.minOrder) || coupon.minOrder < 0) {
    return '优惠券信息异常，请刷新后重试'
  }
  const endText: string = (coupon.endTime ?? '').trim()
  const endTime: number = endText === '' ? Number.NaN : Date.parse(endText.replace(/-/g, '/'))
  if (!/^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$/.test(endText) || !Number.isFinite(endTime)) {
    return '有效期信息异常，请刷新优惠券'
  }
  if (endTime < now) { return '优惠券已过期' }
  if (coupon.used) { return '优惠券已使用或已失效' }
  if (coupon.id === rejectedCouponId) { return '本次提交未能使用，请刷新优惠券后重试' }
  if ((coupon.storeId ?? 0) !== 0 && coupon.storeId !== storeId) { return '仅限指定店铺使用' }
  const goodsCents: number = checkoutCents(goodsAmount)
  if (!Number.isFinite(goodsCents) || !Number.isFinite(deliveryFee) || deliveryFee < 0) {
    return '订单金额待确认，请返回购物车刷新'
  }
  if (goodsCents / 100 < coupon.minOrder) {
    return `商品满 ¥${coupon.minOrder.toFixed(2)} 可用，配送费不计门槛`
  }
  if (goodsCents + checkoutCents(deliveryFee) - checkoutCents(coupon.amount) <= 0) {
    return '抵扣后应付须大于 ¥0.00，请更换优惠券'
  }
  return ''
}
