import { UIAbility } from '@kit.AbilityKit'
import { pushService, pushCommon } from '@kit.PushKit'
import { post, ApiResponse, getAuthToken, getAuthSessionEpoch } from './HttpClient'
import { User } from '../model/Models'
import { logInfo, logWarn } from './AppLogger'

interface PushTokenRequest { token: string }
interface PushRegistrationResult { profileId: string }

let deviceToken: string = ''
let profileId: string = ''
let registeredUserId: number = 0
let inFlight: boolean = false
let tokenListenerActive: boolean = false
let retryAfter: number = 0

function isCurrentUser(userId: number, epoch: number): boolean {
  const current: User | undefined = AppStorage.get<User>('user')
  return AppStorage.get<boolean>('privacyConsent') === true && AppStorage.get<boolean>('isLoggedIn') === true &&
    current !== undefined && current.id === userId && getAuthSessionEpoch() === epoch && getAuthToken() !== ''
}

export function initializePushKit(ability: UIAbility): void {
  if (!tokenListenerActive) {
    try {
      pushService.on('tokenUpdate', ability, (token: string): void => {
        deviceToken = token
        registeredUserId = 0
        retryAfter = 0
        registerPushForCurrentSession()
      })
      tokenListenerActive = true
    } catch (_) {
      logWarn('Push', '当前设备不可监听推送 Token，订单仍可正常查询')
    }
  }
  registerPushForCurrentSession()
}

export async function registerPushForCurrentSession(): Promise<void> {
  const user: User | undefined = AppStorage.get<User>('user')
  const epoch: number = getAuthSessionEpoch()
  if (inFlight || user === undefined || !isCurrentUser(user.id, epoch) ||
    registeredUserId === user.id || Date.now() < retryAfter) { return }
  inFlight = true
  try {
    const token: string = deviceToken === '' ? await pushService.getToken() : deviceToken
    if (!isCurrentUser(user.id, epoch)) { return }
    deviceToken = token
    const request: PushTokenRequest = { token: token }
    const response: ApiResponse<PushRegistrationResult> = await post<PushRegistrationResult>(
      '/api/auth/push-token', request, false)
    if (!isCurrentUser(user.id, epoch)) { return }
    if (response.code !== 200 || response.data === undefined || response.data === null ||
      response.data.profileId === '') {
      throw new Error('Push token registration failed')
    }
    await pushService.bindAppProfileId(pushCommon.AppProfileType.PROFILE_TYPE_APPLICATION_ACCOUNT,
      response.data.profileId)
    if (!isCurrentUser(user.id, epoch)) {
      await pushService.unbindAppProfileId(response.data.profileId)
      return
    }
    profileId = response.data.profileId
    registeredUserId = user.id
    AppStorage.setOrCreate<string>('pushRegistrationState', 'registered')
    logInfo('Push', '当前账号已注册设备推送')
  } catch (_) {
    retryAfter = Date.now() + 10 * 60 * 1000
    AppStorage.setOrCreate<string>('pushRegistrationState', 'unavailable')
    logWarn('Push', '推送未启用：请在 AGC 开通服务并重新签发具备 Push Kit 能力的 Profile；登录与订单不受影响')
  } finally {
    inFlight = false
  }
}

export function currentPushToken(): string {
  return deviceToken
}

export function clearPushIdentity(): void {
  const previousProfileId: string = profileId
  deviceToken = ''
  profileId = ''
  registeredUserId = 0
  retryAfter = 0
  AppStorage.setOrCreate<string>('pushRegistrationState', 'idle')
  if (previousProfileId !== '') {
    pushService.unbindAppProfileId(previousProfileId).catch(() => {
      logWarn('Push', '设备推送账号解绑未完成，后续登录将重新绑定')
    })
  }
  pushService.deleteToken().catch(() => {
    logWarn('Push', '设备推送 Token 清理未完成，后续登录将重新注册')
  })
}

export function disposePushKit(): void {
  if (tokenListenerActive) {
    try { pushService.off('tokenUpdate') } catch (_) {}
    tokenListenerActive = false
  }
}
