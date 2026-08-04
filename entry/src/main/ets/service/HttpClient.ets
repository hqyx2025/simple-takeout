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

// GET请求
export async function get<T>(url: string, params?: Record<string, string>): Promise<ApiResponse<T>> {
  if (USE_MOCK) {
    // Mock模式：直接返回空数据结构，实际数据由调用方从MockDataService获取
    const response: ApiResponse<T> = {
      code: 200,
      message: 'success',
      data: {} as T
    }
    return response
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
    const response: ApiResponse<T> = {
      code: 200,
      message: 'success',
      data: {} as T
    }
    return response
  }
  const response: AxiosResponse<ApiResponse<T>> = await getClient().post(url, data)
  return response.data
}

// PUT请求
export async function put<T>(url: string, data?: Record<string, string>): Promise<ApiResponse<T>> {
  if (USE_MOCK) {
    const response: ApiResponse<T> = {
      code: 200,
      message: 'success',
      data: {} as T
    }
    return response
  }
  const response: AxiosResponse<ApiResponse<T>> = await getClient().put(url, data)
  return response.data
}

// DELETE请求
export async function del<T>(url: string): Promise<ApiResponse<T>> {
  if (USE_MOCK) {
    const response: ApiResponse<T> = {
      code: 200,
      message: 'success',
      data: {} as T
    }
    return response
  }
  const response: AxiosResponse<ApiResponse<T>> = await getClient().delete(url)
  return response.data
}

// 切换Mock模式
export function setMockMode(enabled: boolean): void {
  // 注意：USE_MOCK是const，这里仅作为接口预留
  // 实际切换需要重新构建
}
