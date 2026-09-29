#include <stdio.h>
#include <stdlib.h>
#include <errno.h>
#include <sys/stat.h>
#ifdef _WIN32
#include <windows.h>
#include <wchar.h>
static wchar_t *wide_path(const char *text) {
  int size = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text, -1, NULL, 0);
  if (!size) return NULL;
  wchar_t *result = malloc((size_t)size * sizeof(wchar_t));
  if (!result) return NULL;
  if (!MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text, -1, result, size)) {
    free(result); return NULL;
  }
  return result;
}
#endif
int morphir_host_kind(const char *path) {
#ifdef _WIN32
  wchar_t *wide = wide_path(path);
  if (!wide) return -1;
  DWORD a = GetFileAttributesW(wide);
  DWORD e = GetLastError();
  free(wide);
  if (a == INVALID_FILE_ATTRIBUTES)
    return (e == ERROR_FILE_NOT_FOUND || e == ERROR_PATH_NOT_FOUND) ? 0 : -1;
  if (a & FILE_ATTRIBUTE_REPARSE_POINT) return 3;
  return (a & FILE_ATTRIBUTE_DIRECTORY) ? 2 : 1;
#else
  struct stat st;
  if (lstat(path, &st)) return (errno == ENOENT || errno == ENOTDIR) ? 0 : -1;
  if (S_ISLNK(st.st_mode)) return 3;
  if (S_ISDIR(st.st_mode)) return 2;
  if (S_ISREG(st.st_mode)) return 1;
  return 4;
#endif
}
int morphir_host_size(const char *path) {
#ifdef _WIN32
  wchar_t *wide = wide_path(path);
  if (!wide) return -1;
  struct _stat64 st;
  int result = _wstat64(wide, &st);
  free(wide);
  if (result) return -1;
#else
  struct stat st;
  if (stat(path, &st)) return -1;
#endif
  return st.st_size > 16777216 ? 16777217 : (int)st.st_size;
}
int morphir_host_rename(const char *a, const char *b) {
#ifdef _WIN32
  wchar_t *first = wide_path(a), *second = wide_path(b);
  if (!first || !second) { free(first); free(second); return EINVAL; }
  int result = _wrename(first, second) ? errno : 0;
  free(first); free(second);
  return result;
#else
  return rename(a, b) ? errno : 0;
#endif
}
void morphir_host_stderr(const char *text) { fputs(text, stderr); }
void morphir_host_exit(int code) { exit(code); }
int morphir_host_system(void) {
#ifdef __APPLE__
  return 0;
#elif defined(_WIN32)
  return 1;
#else
  return 2;
#endif
}
