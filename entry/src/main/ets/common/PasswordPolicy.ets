export const PASSWORD_SYMBOLS: string = '!@#$%^&*._+-=?'
export const PASSWORD_HINT: string = '6 至 64 位，支持数字、英文字母和 ' + PASSWORD_SYMBOLS

/** 新密码的字符限制不应用于已有账号的登录。 */
export function newPasswordError(value: string): string {
  if (value.length < 6 || value.length > 64) { return '密码需为 6 至 64 位' }
  if (!/^[A-Za-z0-9!@#$%^&*._+=?\-]+$/.test(value)) {
    return '仅支持数字、英文字母和 ' + PASSWORD_SYMBOLS + '，不含空格或其他字符'
  }
  return ''
}

export function passwordStrength(value: string): number {
  if (!value || /[^A-Za-z0-9!@#$%^&*._+=?\-]/.test(value)) { return 0 }
  if (value.length < 6 || !/[0-9]/.test(value) || !/[A-Za-z]/.test(value)) { return 1 }
  return /[!@#$%^&*._+=?\-]/.test(value) ? 3 : 2
}
