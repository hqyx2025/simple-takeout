/** 订单状态：0待付款、1待接单、2制作中、3配送中、4已完成、5已取消、6退款中。 */
export function canTransitionOrderStatus(from: number, to: number): boolean {
  if (from === 0) {
    return to === 1 || to === 5 || to === 6
  }
  if (from === 1) {
    return to === 2 || to === 5
  }
  if (from === 2) {
    return to === 3 || to === 5
  }
  if (from === 3) {
    return to === 4
  }
  return false
}

export function getOrderStatusSequence(): number[] {
  return [0, 1, 2, 3, 4]
}
