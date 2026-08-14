/**
 * 统一网络请求层
 * 基于 @ohos/axios 封装，对接真实后端 API（Spring Boot + MySQL）
 * 所有业务数据经由本层获取，认证使用 JWT Bearer Token
 */
import axios, { AxiosInstance, AxiosRequestConfig, AxiosResponse, AxiosError, AxiosHeaders, AxiosRequestHeaders } from '@ohos/axios'
import { API_CONFIG } from '../common/Constants'
import { logInfo, logWarn, logError } from './AppLogger'

// 是否使用Mock数据（false = 对接真实后端）
const USE_MOCK: boolean = false

// JWT Token（登录成功后由 ApiService 设置，请求时自动注入）
let authToken: string = ''

export function setAuthToken(token: string): void {
  authToken = token
}

export function getAuthToken(): string {
  return authToken
}

// 创建axios实例
let httpClient: AxiosInstance | null = null

// 构造请求头（自动注入 JWT）
function buildHeaders(): AxiosRequestHeaders {
  const headers: AxiosRequestHeaders = new AxiosHeaders() as AxiosRequestHeaders
  headers.set('Content-Type', 'application/json')
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

/**
 * 核心请求方法：返回后端 ApiResponse；网络异常时返回 code=500 的错误响应
 */
async function request<T>(method: string, url: string, data?: Object): Promise<ApiResponse<T>> {
  if (USE_MOCK) {
    return createMockResponse<T>()
  }
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
    return response.data
  } catch (err) {
    const axiosErr: AxiosError = err as AxiosError
    const resp: ApiResponse<T> = axiosErr.response?.data as ApiResponse<T>
    if (resp !== undefined && resp !== null && resp.code !== undefined) {
      logWarn('Http', `${method} ${url} 业务失败 code=${resp.code} msg=${resp.message}`)
      if (resp.code === 401) {
        // 认证失效时立即清理内存态和 UI 登录态，避免“界面已登录但接口全部 401”。
        setAuthToken('')
        AppStorage.setOrCreate<string>('authToken', '')
        AppStorage.setOrCreate<boolean>('isLoggedIn', false)
      }
      return resp
    }
    logError('Http', `${method} ${url} 请求异常`, err)
    return { code: 500, message: '网络请求失败，请确认后端服务已启动', data: (MockEmptyData.create() as object) as T }
  }
}

/**
 * Mock 模式空数据占位类型。
 * Mock 模式下实际数据由调用方从 MockDataService 获取，此处仅保证结构完整。
 */
class MockEmptyData {
  static create(): MockEmptyData {
    return new MockEmptyData()
  }
}

// 构造 Mock 模式空响应
function createMockResponse<T>(): ApiResponse<T> {
  const response: ApiResponse<T> = {
    code: 200,
    message: 'success',
    data: (MockEmptyData.create() as object) as T
  }
  return response
}

// GET请求
export async function get<T>(url: string): Promise<ApiResponse<T>> {
  return request<T>('GET', url)
}

// POST请求
export async function post<T>(url: string, data?: Object): Promise<ApiResponse<T>> {
  return request<T>('POST', url, data)
}

// PUT请求
export async function put<T>(url: string, data?: Object): Promise<ApiResponse<T>> {
  return request<T>('PUT', url, data)
}

// DELETE请求
export async function del<T>(url: string): Promise<ApiResponse<T>> {
  return request<T>('DELETE', url)
}

// 切换Mock模式（预留）
export function setMockMode(enabled: boolean): void {
  logInfo('Http', `Mock 模式切换请求：${enabled}（需重新构建生效）`)
}
