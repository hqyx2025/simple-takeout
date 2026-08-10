/**
 * 统一网络请求层
 * 基于 @ohos/axios 封装，当前对接本地Mock数据
 * 结构上支持切换真实后端API
 */
import axios, { AxiosInstance, AxiosRequestConfig, AxiosResponse } from '@ohos/axios'
import { API_CONFIG } from '../common/Constants'

// 是否使用Mock数据（当前为true，后续对接真实API时改为false）
const USE_MOCK: boolean = true

// 创建axios实例（仅在不使用Mock时初始化）
let httpClient: AxiosInstance | null = null

function getClient(): AxiosInstance {
  if (httpClient === null) {
    httpClient = axios.create({
      baseURL: API_CONFIG.BASE_URL,
      timeout: API_CONFIG.TIMEOUT,
      headers: {
        'Content-Type': 'application/json'
      }
    })
  }
  return httpClient
}

// 统一响应数据结构
export interface ApiResponse<T> {
  code: number
  message: string
  data: T
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

// 构造 Mock 模式空响应（避免无类型对象字面量 arkts-no-untyped-obj-literals）
function createMockResponse<T>(): ApiResponse<T> {
  const response: ApiResponse<T> = {
    code: 200,
    message: 'success',
    data: (MockEmptyData.create() as object) as T
  }
  return response
}

// GET请求
export async function get<T>(url: string, params?: Record<string, string>): Promise<ApiResponse<T>> {
  if (USE_MOCK) {
    return createMockResponse<T>()
  }
  const config: AxiosRequestConfig = {
    params: params
  }
  const response: AxiosResponse<ApiResponse<T>> = await getClient().get(url, config)
  return response.data
}

// POST请求
export async function post<T>(url: string, data?: Record<string, string>): Promise<ApiResponse<T>> {
  if (USE_MOCK) {
    return createMockResponse<T>()
  }
  const response: AxiosResponse<ApiResponse<T>> = await getClient().post(url, data)
  return response.data
}

// PUT请求
export async function put<T>(url: string, data?: Record<string, string>): Promise<ApiResponse<T>> {
  if (USE_MOCK) {
    return createMockResponse<T>()
  }
  const response: AxiosResponse<ApiResponse<T>> = await getClient().put(url, data)
  return response.data
}

// DELETE请求
export async function del<T>(url: string): Promise<ApiResponse<T>> {
  if (USE_MOCK) {
    return createMockResponse<T>()
  }
  const response: AxiosResponse<ApiResponse<T>> = await getClient().delete(url)
  return response.data
}

// 切换Mock模式
export function setMockMode(enabled: boolean): void {
  // 注意：USE_MOCK是const，这里仅作为接口预留
  // 实际切换需要重新构建
}
