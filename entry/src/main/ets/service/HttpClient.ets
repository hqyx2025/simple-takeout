/**
 * 统一网络请求层
 * 基于 @ohos/axios 封装，对接真实后端 API（Spring Boot + MySQL）
 * 所有业务数据经由本层获取，认证使用 JWT Bearer Token
 */
import axios, { AxiosInstance, AxiosRequestConfig, AxiosResponse, AxiosError, AxiosHeaders, AxiosRequestHeaders } from '@ohos/axios'
import { API_CONFIG } from '../common/Constants'
import { logInfo, logWarn, logError } from './AppLogger'

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
async function request<T>(method: string, url: string, data?: Object): Promise<ApiResponse<T>> {
  const operation: string = getOperationName(method, url)
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
      logInfo('Http', `后端响应成功：${operation}，状态码=${result.code}，消息=${result.message}`)
    } else {
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
    return { code: 500, message: '网络请求失败，请确认后端服务已启动', data: undefined as T }
  }
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
