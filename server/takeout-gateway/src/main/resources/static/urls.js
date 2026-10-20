(() => {
  'use strict';
  // Resolve service paths beneath the page directory, both at / and /takeout/.
  const localPath = (value, base) => {
    if (!value || !value.startsWith('/') || value.startsWith('//')) return value;
    const directory = new URL('.', base);
    if (value.startsWith(directory.pathname)) return value;
    return directory.pathname.replace(/\/$/, '') + value;
  };
  globalThis.TakeoutUrls = { localPath };
})();
