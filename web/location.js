/* Device coordinates are WGS84; the server converts them to the map's GCJ02. */
(() => {
  'use strict';
  function devicePosition(environment = globalThis) {
    if (!environment.isSecureContext) return Promise.reject(new Error('精确定位需要 HTTPS，请打开安全定位入口，或手动搜索地点。'));
    if (!environment.navigator?.geolocation) return Promise.reject(new Error('当前浏览器不支持设备定位，请搜索地点或手动输入地址。'));
    return new Promise((resolve, reject) => {
      environment.navigator.geolocation.getCurrentPosition(position => {
        const { longitude, latitude, accuracy } = position.coords;
        if (!Number.isFinite(longitude) || !Number.isFinite(latitude) || Math.abs(longitude) > 180 || Math.abs(latitude) > 90 || (longitude === 0 && latitude === 0)) {
          reject(new Error('设备返回了无效坐标，请重试或搜索地点。')); return;
        }
        resolve({ longitude, latitude, accuracy });
      }, error => reject(new Error({
        1: '位置权限未开启。请在浏览器站点设置中允许位置访问，或手动搜索地点。',
        2: '暂时无法获取设备位置，请检查系统定位服务，或手动搜索地点。',
        3: '定位超时，请移至信号较好的位置重试，或手动搜索地点。'
      }[error.code] || '定位失败，请重试或手动搜索地点。')), { enableHighAccuracy: true, timeout: 12000, maximumAge: 0 });
    });
  }
  const coordinates = (longitude, latitude) => {
    if (longitude === '' || latitude === '' || longitude == null || latitude == null) return null;
    const lng = Number(longitude), lat = Number(latitude);
    return Number.isFinite(lng) && Number.isFinite(lat) && Math.abs(lng) <= 180 && Math.abs(lat) <= 90 && (lng !== 0 || lat !== 0) ? { longitude:lng, latitude:lat } : null;
  };
  function place(poi) {
    if (!poi || typeof poi.location !== 'string') return null;
    const parts = poi.location.split(',');
    if (parts.length !== 2) return null;
    const coordinate = coordinates(parts[0].trim(), parts[1].trim());
    const address = [poi.pname, poi.cityname === poi.pname ? '' : poi.cityname, poi.adname, poi.address, poi.name].filter(value => typeof value === 'string' && value.trim()).join('');
    return coordinate && address ? { ...coordinate, address } : null;
  }
  globalThis.TakeoutLocation = { devicePosition, coordinates, place };
})();
