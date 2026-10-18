/**
 * 统一网络请求层
 * 基于系统 RCP 共享会话封装，对接真实后端 API（Spring Boot + MySQL）
 * 所有业务数据经由本层获取，认证使用 JWT Bearer Token
 */
import { clearDeliveryForms } from './DeliveryFormSync'
import { rcp } from '@kit.RemoteCommunicationKit'
import http from '@ohos.net.http'
import fileIo from '@ohos.file.fs'
import { API_CONFIG } from '../common/Constants'
import { UploadResult } from '../model/Models'
import { logInfo, logWarn, logError } from './AppLogger'
import { promptCompat as promptAction } from '../common/UiNavigation'
import { clearAuthTokens, saveAuthTokens } from './TokenStorage'

// JWT Token（登录成功后由 ApiService 设置，请求时自动注入）
let authToken: string = ''
let refreshToken: string = ''
let authSessionEpoch: number = 0
let refreshInFlight: Promise<number> | null = null
let sessionExpiredHandler: (() => Promise<void>) | null = null
let lastApiErrorMessage: string = ''
let lastToastMessage: string = ''
let lastToastAt: number = 0
let serverClockOffsetMs: number = 0

export function setAuthToken(token: string): void {
  setAuthTokens(token, token === '' ? '' : refreshToken)
}

export function setAuthTokens(accessToken: string, nextRefreshToken: string): void {
  if (authToken !== accessToken || refreshToken !== nextRefreshToken || accessToken === '') {
    clearDeliveryForms()
  }
  authToken = accessToken
  refreshToken = nextRefreshToken
  authSessionEpoch += 1
}

export function getRefreshToken(): string {
  return refreshToken
}

export function getAuthSessionEpoch(): number {
  return authSessionEpoch
}

export function registerSessionExpiredHandler(handler: () => Promise<void>): void {
  sessionExpiredHandler = handler
}

export function getAuthToken(): string {
  return authToken
}

export function getLastApiErrorMessage(): string {
  return lastApiErrorMessage
}

/** 最近一次响应的服务端时间偏移，兼容旧接口未返回 serverNowEpochMs 的订单数据。 */
export function getServerClockOffsetMs(): number {
  return serverClockOffsetMs
}

/** 当前服务端时间估值，业务截止时间不要直接使用设备 Date.now()。 */
export function getServerNowEpochMs(): number {
  return Date.now() + serverClockOffsetMs
}

function notifyApiError(message: string): void {
  const text: string = message.trim()
  if (text === '') {
    return
  }
  const now: number = Date.now()
  if (text === lastToastMessage && now - lastToastAt < 3000) {
    return
  }
  lastToastMessage = text
  lastToastAt = now
  promptAction.showToast({ message: text, duration: 3000 })
}

// 预建链与业务请求必须共享同一会话，否则无法复用已建立的连接。
let httpClient: rcp.Session | null = null
let coldConnectionStarted: boolean = false

export function warmColdStartConnection(): void {
  if (coldConnectionStarted || !(AppStorage.get<boolean>('privacyConsent') ?? false)) {
    return
  }
  coldConnectionStarted = true
  try {
    const warmup: rcp.Request = new rcp.Request(API_CONFIG.BASE_URL)
    warmup.connectOnly = true
    warmup.configuration = { transfer: { timeout: { connectMs: 1500, transferMs: 1500 } } }
    // 不发送 HTTP 业务请求和令牌，不等待预连接完成再绘制首屏。
    getClient().fetch(warmup).then(() => {
      logInfo('Network', '冷启动预建链完成')
    }).catch(() => {
      logInfo('Network', '预建链未完成，业务请求按正常流程连接')
    })
  } catch (_) {
    logInfo('Network', '当前设备预建链不可用，业务请求按正常流程连接')
  }
}

export function disposeHttpClient(): void {
  if (httpClient !== null) {
    try { httpClient.close() } catch (_) {}
  }
  httpClient = null
  coldConnectionStarted = false
}

function buildHeaders(token: string = authToken): Record<string, string> {
  const headers: Record<string, string> = {
    'Content-Type': 'application/json',
    'Cache-Control': 'no-cache, no-store, max-age=0',
    'Pragma': 'no-cache',
    'Expires': '0'
  }
  if (token !== '') { headers['Authorization'] = `Bearer ${token}` }
  return headers
}

function getClient(): rcp.Session {
  if (httpClient === null) {
    httpClient = rcp.createSession({ requestConfiguration: {
      transfer: { timeout: { connectMs: API_CONFIG.TIMEOUT, transferMs: API_CONFIG.TIMEOUT } }
    } })
  }
  return httpClient
}

// 统一响应数据结构（与后端 ApiResponse 对齐）
export interface ApiResponse<T> {
  code: number
  message: string
  data: T
}

interface RefreshedTokenData {
  token: string
  refreshToken: string
}

// 将接口路径转换为用户可读的中文操作名称，便于在 DevEco 日志中追踪前后端联调。
function getOperationName(method: string, url: string): string {
  const action: string = method === 'GET' ? '查询' : method === 'POST' ? '提交' : method === 'PUT' ? '修改' : '删除'
  if (url.indexOf('/auth/login') >= 0) {
    return '用户登录'
  }
  if (url.indexOf('/auth/register') >= 0) {
    return '用户注册'
  }
  if (url.indexOf('/categories') >= 0) {
    return `${action}菜品分类`
  }
  if (url.indexOf('/search') >= 0) {
    return '搜索店铺'
  }
  if (url.indexOf('/merchant/stats') >= 0) {
    return '查询商户经营统计'
  }
  if (url.indexOf('/merchant/orders') >= 0) {
    return '处理商户订单'
  }
  if (url.indexOf('/merchant/stores') >= 0) {
    return '管理商户店铺'
  }
  if (url.indexOf('/orders') >= 0) {
    return `${action}用户订单`
  }
  if (url.indexOf('/favorites') >= 0) {
    return '同步收藏'
  }
  if (url.indexOf('/coupons') >= 0) {
    return '处理优惠券'
  }
  if (url.indexOf('/addresses') >= 0) {
    return '处理收货地址'
  }
  if (url.indexOf('/stores') >= 0) {
    return `${action}店铺信息`
  }
  return `${action}后端数据`
}

/**
 * 核心请求方法：返回后端 ApiResponse；网络异常时返回 code=500 的错误响应
 */
async function request<T>(method: string, url: string, data?: Object, showErrorToast: boolean = true,
  timeoutMs: number = API_CONFIG.TIMEOUT): Promise<ApiResponse<T>> {
  const requestToken: string = authToken
  const requestRefreshToken: string = refreshToken
  const requestEpoch: number = authSessionEpoch
  const operation: string = getOperationName(method, url)
  lastApiErrorMessage = ''
  logInfo('Http', `前端请求后端：${operation}（${method} ${url}）`)
  try {
    let attempt: ApiResponse<T> = await performRequest<T>(method, url, data, timeoutMs, requestToken)
    if (attempt.code === 401 && url !== '/api/auth/refresh' && url !== '/api/auth/logout') {
      const refreshResult: number = await refreshAfterUnauthorized(requestToken, requestRefreshToken, requestEpoch)
      if (refreshResult === 1 && authSessionEpoch === requestEpoch) {
        attempt = await performRequest<T>(method, url, data, timeoutMs, authToken)
        if (attempt.code === 401 && authSessionEpoch === requestEpoch) {
          await expireLocalSession()
        }
      } else if (refreshResult === -1 && authSessionEpoch === requestEpoch) {
        await expireLocalSession()
      }
    }
    const result: ApiResponse<T> = attempt
    if (result.code === 200) {
      lastApiErrorMessage = ''
      logInfo('Http', `后端响应成功：${operation}，状态码=${result.code}，消息=${result.message}`)
    } else {
      lastApiErrorMessage = result.message || ''
      if (showErrorToast) {
        notifyApiError(lastApiErrorMessage)
      }
      logWarn('Http', `后端业务失败：${operation}，状态码=${result.code}，消息=${result.message}`)
    }
    return result
  } catch (err) {
    logError('Http', `后端请求异常：${operation}，请检查网络和服务端状态`, err)
    lastApiErrorMessage = '网络请求失败，请确认后端服务已启动'
    if (showErrorToast) {
      notifyApiError(lastApiErrorMessage)
    }
    return { code: 500, message: '网络请求失败，请确认后端服务已启动', data: undefined as T }
  }
}

async function performRequest<T>(method: string, url: string, data: Object | undefined, timeoutMs: number,
  token: string): Promise<ApiResponse<T>> {
  const nativeRequest: rcp.Request = new rcp.Request(API_CONFIG.BASE_URL + url,
    method as rcp.HttpMethod, buildHeaders(token), data === undefined ? undefined : JSON.stringify(data))
  nativeRequest.configuration = { transfer: { timeout: { connectMs: API_CONFIG.TIMEOUT, transferMs: timeoutMs } } }
  const response: rcp.Response = await getClient().fetch(nativeRequest)
  const dateHeader: string | string[] | undefined = response.headers.date
  const dateText: string = typeof dateHeader === 'string' ? dateHeader : ''
  const serverEpochMs: number = Date.parse(dateText)
  if (Number.isFinite(serverEpochMs)) {
    serverClockOffsetMs = serverEpochMs - Date.now()
  }
  let parsed: ApiResponse<T> | null = null
  try { parsed = response.toJSON() as ApiResponse<T> | null } catch (_) {}
  const result: ApiResponse<T> = parsed !== null && typeof parsed.code === 'number'
    ? parsed : { code: response.statusCode >= 400 ? response.statusCode : 502,
      message: response.statusCode === 401 ? '登录已过期，请重新登录' : '服务响应异常，请稍后重试', data: undefined as T }
  if (response.statusCode === 401) { result.code = 401 }
  return result
}

async function refreshAfterUnauthorized(staleAccessToken: string, staleRefreshToken: string, epoch: number): Promise<number> {
  if (authSessionEpoch !== epoch) { return 2 }
  if (authToken !== staleAccessToken || refreshToken !== staleRefreshToken) {
    return authToken !== '' ? 1 : -1
  }
  if (refreshToken === '') { return -1 }
  if (refreshInFlight !== null) { return await refreshInFlight }
  refreshInFlight = (async (): Promise<number> => {
    try {
      const nativeRequest: rcp.Request = new rcp.Request(API_CONFIG.BASE_URL + '/api/auth/refresh',
        'POST' as rcp.HttpMethod, buildHeaders(''), JSON.stringify({ refreshToken: staleRefreshToken }))
      nativeRequest.configuration = { transfer: { timeout: { connectMs: API_CONFIG.TIMEOUT, transferMs: API_CONFIG.TIMEOUT } } }
      const response: rcp.Response = await getClient().fetch(nativeRequest)
      if (authSessionEpoch !== epoch || authToken !== staleAccessToken || refreshToken !== staleRefreshToken) { return 2 }
      let parsed: ApiResponse<RefreshedTokenData> | null = null
      try { parsed = response.toJSON() as ApiResponse<RefreshedTokenData> | null } catch (_) {}
      if (response.statusCode === 401 || parsed?.code === 401 || parsed?.code === 400 || parsed?.code === 403) { return -1 }
      if (response.statusCode >= 500 || response.statusCode < 200 || response.statusCode >= 300 || parsed === null ||
        parsed.code !== 200 || parsed.data === undefined || parsed.data === null ||
        typeof parsed.data.token !== 'string' || typeof parsed.data.refreshToken !== 'string') { return 0 }
      authToken = parsed.data.token
      refreshToken = parsed.data.refreshToken
      AppStorage.setOrCreate<string>('authToken', authToken)
      try {
        await saveAuthTokens(authToken, refreshToken)
      } catch (_) {
        logWarn('Auth', '安全存储不可用，本次运行保持登录；下次启动需要重新登录')
      }
      return 1
    } catch (_) {
      return 0
    } finally {
      refreshInFlight = null
    }
  })()
  return await refreshInFlight
}

async function expireLocalSession(): Promise<void> {
  authToken = ''
  refreshToken = ''
  authSessionEpoch += 1
  clearDeliveryForms()
  AppStorage.setOrCreate<string>('authToken', '')
  if (sessionExpiredHandler !== null) {
    await sessionExpiredHandler()
  } else {
    AppStorage.setOrCreate<boolean>('isLoggedIn', false)
    await clearAuthTokens()
  }
}

// GET请求
export async function get<T>(url: string): Promise<ApiResponse<T>> {
  return request<T>('GET', url)
}

// POST请求
export async function post<T>(url: string, data?: Object, showErrorToast: boolean = true,
  timeoutMs: number = API_CONFIG.TIMEOUT): Promise<ApiResponse<T>> {
  return request<T>('POST', url, data, showErrorToast, timeoutMs)
}

// PUT请求
export async function put<T>(url: string, data?: Object): Promise<ApiResponse<T>> {
  return request<T>('PUT', url, data)
}

// DELETE请求
export async function del<T>(url: string): Promise<ApiResponse<T>> {
  return request<T>('DELETE', url)
}

/**
 * 图片上传（multipart/form-data）。
 * axios 的 FormData 在本工程 ArkTS 环境下对本地文件 URI 支持不稳定，因此改用
 * @ohos.net.http 的 multiFormDataList 直接提交文件二进制，保证真机/模拟器一致。
 * 注意：file.picker 返回的 URI 为 file://datashare://... ，需用 fileIo 读成 ArrayBuffer 后上传。
 */
export async function uploadFile(url: string, fileUri: string, showErrorToast: boolean = true): Promise<UploadResult | null> {
  const requestToken: string = authToken
  const requestRefreshToken: string = refreshToken
  const requestEpoch: number = authSessionEpoch
  lastApiErrorMessage = ''
  let file: fileIo.File | null = null
  // 请求对象在 finally 中统一 destroy，避免上传失败/异常时连接资源泄漏
  let httpRequest: http.HttpRequest | null = null
  try {
    httpRequest = http.createHttp()
    file = fileIo.openSync(fileUri, fileIo.OpenMode.READ_ONLY)
    const stat: fileIo.Stat = fileIo.statSync(file.fd)
    const buffer: ArrayBuffer = new ArrayBuffer(stat.size)
    fileIo.readSync(file.fd, buffer)

    const fileName: string = buildFileName(fileUri)
    const formData: http.MultiFormData = {
      name: 'file',
      contentType: buildContentType(fileName),
      remoteFileName: fileName,
      data: buffer
    }
    const header: Record<string, string> = {
      'Content-Type': 'multipart/form-data',
      'Authorization': `Bearer ${authToken}`
    }
    const options: http.HttpRequestOptions = {
      method: http.RequestMethod.POST,
      header: header,
      multiFormDataList: [formData],
      expectDataType: http.HttpDataType.STRING,
      connectTimeout: API_CONFIG.TIMEOUT,
      readTimeout: API_CONFIG.TIMEOUT
    }
    logInfo('Http', `前端请求后端：上传评价图片（POST ${url}）`)
    const response: http.HttpResponse = await httpRequest.request(url, options)
    const body: string = typeof response.result === 'string' ? response.result as string : ''
    if (response.responseCode !== 200 || body === '') {
      if (response.responseCode === 401) {
        const refreshResult: number = await refreshAfterUnauthorized(requestToken, requestRefreshToken, requestEpoch)
        if (refreshResult === -1 && authSessionEpoch === requestEpoch) { await expireLocalSession() }
      }
      lastApiErrorMessage = '图片上传失败，请稍后重试'
      if (showErrorToast) {
        notifyApiError(lastApiErrorMessage)
      }
      return null
    }
    const parsed: ApiResponse<UploadResult> = JSON.parse(body) as ApiResponse<UploadResult>
    if (parsed.code === 401) {
      const refreshResult: number = await refreshAfterUnauthorized(requestToken, requestRefreshToken, requestEpoch)
      if (refreshResult === -1 && authSessionEpoch === requestEpoch) { await expireLocalSession() }
    }
    if (parsed.code !== 200 || parsed.data === undefined || parsed.data === null) {
      lastApiErrorMessage = parsed.message !== undefined && parsed.message !== '' ? parsed.message : '图片上传失败'
      if (showErrorToast) {
        notifyApiError(lastApiErrorMessage)
      }
      return null
    }
    logInfo('Http', `后端响应成功：上传评价图片，地址=${parsed.data.url}`)
    return parsed.data
  } catch (err) {
    logError('Http', '后端请求异常：上传评价图片，请检查网络和服务端状态', err)
    lastApiErrorMessage = '图片上传失败，请确认后端服务已启动'
    if (showErrorToast) {
      notifyApiError(lastApiErrorMessage)
    }
    return null
  } finally {
    if (file !== null) {
      try {
        fileIo.closeSync(file)
      } catch (closeErr) {
        logWarn('Http', '关闭上传文件失败')
      }
    }
    if (httpRequest !== null) {
      try {
        httpRequest.destroy()
      } catch (destroyErr) {
        logWarn('Http', '释放上传请求对象失败')
      }
    }
  }
}

/** 从 URI 中取文件名（无扩展名时按 jpg 处理）。 */
function buildFileName(uri: string): string {
  const index: number = uri.lastIndexOf('/')
  const name: string = index >= 0 ? uri.substring(index + 1) : uri
  return name.indexOf('.') >= 0 ? name : `${name}.jpg`
}

function buildContentType(fileName: string): string {
  const lower: string = fileName.toLowerCase()
  if (lower.endsWith('.png')) {
    return 'image/png'
  }
  if (lower.endsWith('.webp')) {
    return 'image/webp'
  }
  if (lower.endsWith('.gif')) {
    return 'image/gif'
  }
  return 'image/jpeg'
}
