/**
 * 统一网络请求层
 * 基于 @ohos/axios 封装，对接真实后端 API（Spring Boot + MySQL）
 * 所有业务数据经由本层获取，认证使用 JWT Bearer Token
 */
import axios, { AxiosInstance, AxiosRequestConfig, AxiosResponse, AxiosError, AxiosHeaders, AxiosRequestHeaders } from '@ohos/axios'
import http from '@ohos.net.http'
import fileIo from '@ohos.file.fs'
import { API_CONFIG } from '../common/Constants'
import { UploadResult } from '../model/Models'
import { logInfo, logWarn, logError } from './AppLogger'
import { promptCompat as promptAction } from '../common/UiNavigation'

// JWT Token（登录成功后由 ApiService 设置，请求时自动注入）
let authToken: string = ''
let lastApiErrorMessage: string = ''

export function setAuthToken(token: string): void {
  authToken = token
}

export function getAuthToken(): string {
  return authToken
}

export function getLastApiErrorMessage(): string {
  return lastApiErrorMessage
}

function notifyApiError(message: string): void {
  const text: string = message.trim()
  if (text === '') {
    return
  }
  promptAction.showToast({ message: text, duration: 3000 })
}

// 创建axios实例
let httpClient: AxiosInstance | null = null

// 构造请求头（自动注入 JWT）
function buildHeaders(): AxiosRequestHeaders {
  const headers: AxiosRequestHeaders = new AxiosHeaders() as AxiosRequestHeaders
  headers.set('Content-Type', 'application/json')
  // 余额等账户数据必须每次从数据库读取，避免设备/代理层复用旧 GET 响应。
  headers.set('Cache-Control', 'no-cache, no-store, max-age=0')
  headers.set('Pragma', 'no-cache')
  headers.set('Expires', '0')
  if (authToken !== '') {
    headers.set('Authorization', `Bearer ${authToken}`)
  }
  return headers
}

function getClient(): AxiosInstance {
  if (httpClient === null) {
    httpClient = axios.create({
      baseURL: API_CONFIG.BASE_URL,
      timeout: API_CONFIG.TIMEOUT,
      headers: buildHeaders()
    })
  }
  return httpClient
}

// 统一响应数据结构（与后端 ApiResponse 对齐）
export interface ApiResponse<T> {
  code: number
  message: string
  data: T
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
async function request<T>(method: string, url: string, data?: Object, showErrorToast: boolean = true): Promise<ApiResponse<T>> {
  const operation: string = getOperationName(method, url)
  lastApiErrorMessage = ''
  logInfo('Http', `前端请求后端：${operation}（${method} ${url}）`)
  try {
    const config: AxiosRequestConfig = {
      headers: buildHeaders()
    }
    let response: AxiosResponse<ApiResponse<T>>
    if (method === 'GET') {
      response = await getClient().get(url, config)
    } else if (method === 'POST') {
      response = await getClient().post(url, data, config)
    } else if (method === 'PUT') {
      response = await getClient().put(url, data, config)
    } else {
      response = await getClient().delete(url, config)
    }
    const result: ApiResponse<T> = response.data
    if (result.code === 200) {
      lastApiErrorMessage = ''
      logInfo('Http', `后端响应成功：${operation}，状态码=${result.code}，消息=${result.message}`)
    } else {
      lastApiErrorMessage = result.message || ''
      if (showErrorToast) {
        notifyApiError(lastApiErrorMessage)
      }
      logWarn('Http', `后端业务失败：${operation}，状态码=${result.code}，消息=${result.message}`)
      if (result.code === 401) {
        // 后端可能使用 HTTP 200 返回业务状态码 401，同样需要清理登录态。
        setAuthToken('')
        AppStorage.setOrCreate<string>('authToken', '')
        AppStorage.setOrCreate<boolean>('isLoggedIn', false)
      }
    }
    return result
  } catch (err) {
    const axiosErr: AxiosError = err as AxiosError
    const resp: ApiResponse<T> = axiosErr.response?.data as ApiResponse<T>
    if (resp !== undefined && resp !== null && resp.code !== undefined) {
      lastApiErrorMessage = resp.message || ''
      if (showErrorToast) {
        notifyApiError(lastApiErrorMessage)
      }
      logWarn('Http', `后端业务失败：${operation}，状态码=${resp.code}，消息=${resp.message}`)
      if (resp.code === 401) {
        // 认证失效时立即清理内存态和 UI 登录态，避免“界面已登录但接口全部 401”。
        setAuthToken('')
        AppStorage.setOrCreate<string>('authToken', '')
        AppStorage.setOrCreate<boolean>('isLoggedIn', false)
      }
      return resp
    }
    logError('Http', `后端请求异常：${operation}，请检查网络和服务端状态`, err)
    lastApiErrorMessage = '网络请求失败，请确认后端服务已启动'
    if (showErrorToast) {
      notifyApiError(lastApiErrorMessage)
    }
    return { code: 500, message: '网络请求失败，请确认后端服务已启动', data: undefined as T }
  }
}

// GET请求
export async function get<T>(url: string): Promise<ApiResponse<T>> {
  return request<T>('GET', url)
}

// POST请求
export async function post<T>(url: string, data?: Object, showErrorToast: boolean = true): Promise<ApiResponse<T>> {
  return request<T>('POST', url, data, showErrorToast)
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
  lastApiErrorMessage = ''
  let file: fileIo.File | null = null
  try {
    const httpRequest: http.HttpRequest = http.createHttp()
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
    httpRequest.destroy()
    const body: string = typeof response.result === 'string' ? response.result as string : ''
    if (response.responseCode !== 200 || body === '') {
      lastApiErrorMessage = '图片上传失败，请稍后重试'
      if (showErrorToast) {
        notifyApiError(lastApiErrorMessage)
      }
      return null
    }
    const parsed: ApiResponse<UploadResult> = JSON.parse(body) as ApiResponse<UploadResult>
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
