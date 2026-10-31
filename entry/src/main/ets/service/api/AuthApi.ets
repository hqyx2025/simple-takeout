import { get, post, put, del, ApiResponse, setAuthTokens, getRefreshToken } from '../HttpClient'
import { saveAuthTokens } from '../TokenStorage'
import { currentPushToken } from '../PushKitService'
import { API_CONFIG } from '../../common/Constants'
import { User, UserRole, BankCard } from '../../model/Models'
import { logInfo, logWarn } from '../AppLogger'
import { ServerUser, ServerBankCard, ServerRevealedBankCard, LoginResult, LogoutRequest, LoginRequest, RegisterRequest, ChangePasswordRequest, ProfileUpdateRequest, RechargeRequest, EmailCodeApiResult, EmailCodeResult, ForgotPasswordRequest, ForgotPaymentPasswordRequest, EmailCodeRequest, BankCardRequest, RevealBankCardRequest, SetPaymentPasswordRequest, RevealBankCardResult, PaymentPasswordResult } from '../../model/server/Contracts'
import { toBankCard, toServerRole, toUser } from '../../model/server/Converters'
import { CaptchaResult, EmailLoginRequest } from '../../model/server/Contracts'

// ==================== 认证 ====================

/**
 * 登录：成功设置 token 并返回用户，失败返回 null
 */
export async function apiLogin(phone: string, password: string, loginType?: string): Promise<User | null> {
  const req: LoginRequest = loginType === undefined
    ? { phone: phone, password: password }
    : { phone: phone, password: password, loginType: loginType }
  const resp: ApiResponse<LoginResult> = await post<LoginResult>(API_CONFIG.ENDPOINTS['login'], req, false)
  return storeLoginSession(resp)
}

export async function apiLoginByEmail(phone: string, email: string, code: string, loginType: string): Promise<User | null> {
  const req: EmailLoginRequest = { phone: phone, email: email, code: code, loginType: loginType }
  const resp: ApiResponse<LoginResult> = await post<LoginResult>('/api/auth/login/email', req, false)
  return storeLoginSession(resp)
}

async function storeLoginSession(resp: ApiResponse<LoginResult>): Promise<User | null> {
  if (resp.code !== 200 || resp.data === null || resp.data === undefined) {
    logWarn('Api', `登录失败：${resp.message}`)
    return null
  }
  const refresh: string = resp.data.refreshToken ?? ''
  setAuthTokens(resp.data.token, refresh)
  try {
    await saveAuthTokens(resp.data.token, refresh)
  } catch (_) {
    logWarn('Auth', '安全凭证无法写入设备密钥存储；本次运行可继续，重启后需要重新登录')
  }
  logInfo('Api', `登录成功 userId=${resp.data.user.id}`)
  return toUser(resp.data.user)
}

/**
 * 注册：成功返回用户，失败返回 null
 */
export async function apiRegister(username: string, phone: string, email: string, code: string, password: string, role: UserRole): Promise<User | null> {
  const req: RegisterRequest = { username: username, phone: phone, email: email, code: code, password: password, role: toServerRole(role) }
  const resp: ApiResponse<ServerUser> = await post<ServerUser>(API_CONFIG.ENDPOINTS['register'], req, false)
  if (resp.code !== 200 || resp.data === null || resp.data === undefined) {
    logWarn('Api', `注册失败：${resp.message}`)
    return null
  }
  logInfo('Api', `注册成功 userId=${resp.data.id}`)
  return toUser(resp.data)
}

/**
 * 登出：把当前 token 交给后端拉黑，使其在剩余有效期内立刻失效。
 * showErrorToast 关闭：退出登录失败只提示不打断（本地登录态无论如何都要清）。
 */
export async function apiLogout(): Promise<boolean> {
  const request: LogoutRequest = { refreshToken: getRefreshToken(), pushToken: currentPushToken() }
  const resp: ApiResponse<string> = await post<string>('/api/auth/logout', request, false)
  if (resp.code !== 200) {
    logWarn('Api', `登出接口失败：${resp.message}`)
    return false
  }
  logInfo('Api', '登出接口成功，当前 token 已加入黑名单')
  return true
}

/**
 * 修改密码：成功后所有旧 token（含当前这个）立即失效，必须重新登录
 */
export async function changePasswordApi(oldPassword: string, newPassword: string): Promise<boolean> {
  const req: ChangePasswordRequest = { oldPassword: oldPassword, newPassword: newPassword }
  const resp: ApiResponse<string> = await put<string>('/api/auth/password', req)
  if (resp.code !== 200) {
    logWarn('Api', `修改密码失败：${resp.message}`)
    return false
  }
  logInfo('Api', '修改密码成功，旧 token 已失效')
  return true
}

export async function fetchCaptchaApi(): Promise<CaptchaResult | null> {
  const response: ApiResponse<CaptchaResult> = await get<CaptchaResult>('/api/auth/captcha', false)
  return response.code === 200 ? response.data ?? null : null
}

export async function checkUsernameAvailableApi(username: string): Promise<boolean | null> {
  const response: ApiResponse<boolean> = await get<boolean>(
    '/api/auth/username-availability?username=' + encodeURIComponent(username.trim()), false)
  return response.code === 200 && typeof response.data === 'boolean' ? response.data : null
}

export async function requestEmailCodeApi(phone: string, email: string, purpose: string, username: string = '', captchaId: string = '', captchaCode: string = ''): Promise<EmailCodeResult> {
  const request: EmailCodeRequest = { phone: phone, email: email, purpose: purpose, username: username, captchaId: captchaId, captchaCode: captchaCode }
  const response: ApiResponse<EmailCodeApiResult> = await post<EmailCodeApiResult>(
    '/api/auth/email-code', request, false)
  const result: EmailCodeResult = { success: response.code === 200, message: response.message ?? '' }
  if (response.code === 200 && response.data !== null && response.data !== undefined
    && response.data.mock === true && typeof response.data.code === 'string') {
    result.code = response.data.code
    result.mock = true
  }
  return result
}

export async function resetLoginPasswordApi(phone: string, email: string, code: string, newPassword: string): Promise<PaymentPasswordResult> {
  const request: ForgotPasswordRequest = { phone: phone, email: email, code: code, newPassword: newPassword }
  const response: ApiResponse<Object> = await post<Object>('/api/auth/password/forgot', request, false)
  return { success: response.code === 200, message: response.message || '' }
}

export async function resetPaymentPasswordApi(phone: string, email: string, code: string, paymentPassword: string): Promise<PaymentPasswordResult> {
  const request: ForgotPaymentPasswordRequest = { phone: phone, email: email, code: code, paymentPassword: paymentPassword }
  const response: ApiResponse<Object> = await post<Object>('/api/auth/payment-password/forgot', request, false)
  return { success: response.code === 200, message: response.message || '' }
}

export async function updateUserProfileApi(username: string, phone: string, email: string,
  currentPassword: string = ''): Promise<User | undefined> {
  const req: ProfileUpdateRequest = { username: username, phone: phone, email: email, currentPassword: currentPassword }
  const resp: ApiResponse<ServerUser> = await put<ServerUser>('/api/auth/me', req)
  if (resp.code !== 200 || resp.data === null || resp.data === undefined) {
    logWarn('Api', `更新个人资料失败：${resp.message}`)
    return undefined
  }
  return toUser(resp.data)
}

export async function fetchCurrentUserApi(): Promise<User | undefined> {
  // /auth/me 是账户余额的权威来源，增加时间戳避免 GET 缓存返回旧余额。
  const resp: ApiResponse<ServerUser> = await get<ServerUser>(`/api/auth/me?refreshAt=${Date.now()}`)
  if (resp.code !== 200 || resp.data === null || resp.data === undefined) {
    logWarn('Api', `获取当前用户失败：${resp.message}`)
    return undefined
  }
  return toUser(resp.data)
}

export async function rechargeBalanceApi(amount: number): Promise<User | undefined> {
  const req: RechargeRequest = { amount: amount }
  const resp: ApiResponse<ServerUser> = await post<ServerUser>(API_CONFIG.ENDPOINTS['recharge'], req)
  if (resp.code !== 200 || resp.data === null || resp.data === undefined) {
    logWarn('Api', `测试充值失败：${resp.message}`)
    return undefined
  }
  const user: User = toUser(resp.data)
  logInfo('Api', `充值接口返回余额=${user.balance.toFixed(2)}`)
  return user
}

export async function fetchBankCardsApi(): Promise<BankCard[] | null> {
  const resp: ApiResponse<ServerBankCard[]> = await get<ServerBankCard[]>('/api/wallet/bank-cards')
  if (resp.code !== 200 || !Array.isArray(resp.data)) {
    return null
  }
  return resp.data.map((card: ServerBankCard) => toBankCard(card))
}

export async function addBankCardApi(bankName: string, cardType: string, fullCardNumber: string): Promise<BankCard | null> {
  const request: BankCardRequest = { bankName: bankName, cardType: cardType, fullCardNumber: fullCardNumber }
  const response: ApiResponse<ServerBankCard> = await post<ServerBankCard>('/api/wallet/bank-cards', request)
  if (response.code !== 200 || response.data === null || response.data === undefined) { return null }
  return toBankCard(response.data)
}

export async function deleteBankCardApi(cardId: number): Promise<boolean> {
  const response: ApiResponse<Object> = await del<Object>(`/api/wallet/bank-cards/${cardId}`)
  return response.code === 200
}

/**
 * 在支付密码校验通过后临时取回完整卡号。调用方必须在使用后立即清理返回值，
 * 本服务层不写入 AppStorage、日志或任何持久化缓存。
 */
export async function revealBankCardApi(cardId: number, paymentPassword: string): Promise<RevealBankCardResult> {
  const request: RevealBankCardRequest = { paymentPassword: paymentPassword }
  const response: ApiResponse<ServerRevealedBankCard> =
    await post<ServerRevealedBankCard>(`/api/wallet/bank-cards/${cardId}/reveal`, request, false)
  if (response.code !== 200 || response.data === null || response.data === undefined) {
    return { cardNumber: null, message: response.message || '支付密码校验失败' }
  }
  const cardNumber: string = typeof response.data.cardNumber === 'string' ? response.data.cardNumber : ''
  if (!/^[0-9]{16,19}$/.test(cardNumber)) {
    return { cardNumber: null, message: '银行卡号响应无效，请稍后重试' }
  }
  return { cardNumber: cardNumber, message: '' }
}

/** 设置或重置支付密码，登录密码只在本次请求中使用，不作本地保存。 */
export async function setPaymentPasswordApi(loginPassword: string, paymentPassword: string): Promise<PaymentPasswordResult> {
  const request: SetPaymentPasswordRequest = { loginPassword: loginPassword, paymentPassword: paymentPassword }
  const response: ApiResponse<Object> = await post<Object>('/api/auth/payment-password', request, false)
  return { success: response.code === 200, message: response.message || '' }
}
