import BuildProfile from 'BuildProfile'
import { UserRole } from '../model/Models'

export interface QuickLoginAccount {
  phone: string
  password: string
  role: UserRole
}

interface QuickLoginConfiguration {
  baseUrl: string
  accounts: QuickLoginAccount[]
}

/** 凭据绑定具体后端，避免云端不可用时把测试口令发送到另一个环境。 */
export function getQuickLoginAccount(role: UserRole, baseUrl: string): QuickLoginAccount | undefined {
  if (!BuildProfile.DEBUG || BuildProfile.QUICK_LOGIN_CONFIG.length === 0) { return undefined }
  try {
    const config: QuickLoginConfiguration = JSON.parse(BuildProfile.QUICK_LOGIN_CONFIG) as QuickLoginConfiguration
    if (config.baseUrl !== baseUrl || !Array.isArray(config.accounts)) { return undefined }
    return config.accounts.find((account: QuickLoginAccount): boolean => {
      return account !== null && account !== undefined && account.role === role
        && typeof account.phone === 'string' && /^1\d{10}$/.test(account.phone)
        && typeof account.password === 'string' && account.password.length >= 16 && account.password.length <= 64
    })
  } catch (_) {
    return undefined
  }
}
