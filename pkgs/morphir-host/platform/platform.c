#include <stdio.h>
#include <stdlib.h>
#include <errno.h>
#include <sys/stat.h>
#include <string.h>
#include "moonbit.h"
#ifndef _WIN32
#include <unistd.h>
#include <signal.h>
#include <sys/wait.h>
#include <time.h>
#endif
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

int morphir_host_architecture(void) {
#if defined(__aarch64__) || defined(_M_ARM64)
  return 0;
#elif defined(__x86_64__) || defined(_M_X64)
  return 1;
#else
  return 2;
#endif
}

moonbit_bytes_t morphir_host_temporary(void) {
#ifdef _WIN32
  return moonbit_make_bytes(0, 0);
#else
  const char *base = getenv("TMPDIR");
  if (!base || !*base) base = "/tmp";
  size_t length = strlen(base) + 40;
  char *path = malloc(length);
  if (!path) return moonbit_make_bytes(0, 0);
  snprintf(path, length, "%s/morphir-toolchain-XXXXXX", base);
  if (!mkdtemp(path)) { free(path); return moonbit_make_bytes(0, 0); }
  moonbit_bytes_t result = moonbit_make_bytes_raw((int32_t)strlen(path));
  memcpy(result, path, strlen(path)); free(path); return result;
#endif
}

static void put_word(unsigned char *data, int value) {
  unsigned int word = (unsigned int)value;
  for (int i = 0; i < 4; i++) data[i] = (unsigned char)(word >> (i * 8));
}

static moonbit_bytes_t process_error(const char *message) {
  int length = (int)strlen(message);
  moonbit_bytes_t result = moonbit_make_bytes_raw(length + 8);
  put_word(result, -1); put_word(result + 4, 0);
  memcpy(result + 8, message, (size_t)length); return result;
}

moonbit_bytes_t morphir_host_process(const char *program, const char *packed,
    int count, const char *cwd, const char *home, int timeout) {
#ifdef _WIN32
  return process_error("Native Windows process adapter unavailable; use the Node host");
#else
  if (count < 0 || count > 1024 || timeout < 1)
    return process_error("Invalid process arguments or timeout");
  char **argv = calloc((size_t)count + 2, sizeof(char *));
  if (!argv) return process_error("Cannot allocate process arguments");
  argv[0] = (char *)program;
  const char *next = packed;
  for (int i = 0; i < count; i++) { argv[i + 1] = (char *)next; next += strlen(next) + 1; }
  FILE *out = tmpfile(), *err = tmpfile();
  if (!out || !err) {
    if (out) fclose(out); if (err) fclose(err); free(argv);
    return process_error("Cannot create process output files");
  }
  pid_t pid = fork();
  if (pid == 0) {
    setpgid(0, 0);
    if (dup2(fileno(out), STDOUT_FILENO) < 0 || dup2(fileno(err), STDERR_FILENO) < 0) _exit(126);
    if (chdir(cwd)) { perror("chdir"); _exit(126); }
    if (*home) {
      const char *path = getenv("PATH");
      size_t length = strlen(home) + (path ? strlen(path) : 0) + 8;
      char *child_path = malloc(length);
      if (!child_path) _exit(126);
      snprintf(child_path, length, "%s/bin:%s", home, path ? path : "");
      setenv("MOON_HOME", home, 1); setenv("PATH", child_path, 1);
      free(child_path);
    }
    execvp(program, argv); perror("execvp"); _exit(127);
  }
  free(argv);
  if (pid < 0) { fclose(out); fclose(err); return process_error("Cannot start child process"); }
  setpgid(pid, pid);
  int status = 0, elapsed = 0, timed_out = 0, oversized = 0;
  struct timespec interval = {0, 10000000};
  for (;;) {
    pid_t waited = waitpid(pid, &status, WNOHANG);
    if (waited == pid) break;
    if (waited < 0 && errno != EINTR) { status = 127 << 8; break; }
    struct stat out_stat, err_stat;
    if (!fstat(fileno(out), &out_stat) && !fstat(fileno(err), &err_stat) &&
        out_stat.st_size + err_stat.st_size > 16777216) oversized = 1;
    if (elapsed >= timeout || oversized) {
      kill(-pid, SIGKILL); kill(pid, SIGKILL);
      while (waitpid(pid, &status, 0) < 0 && errno == EINTR) {}
      timed_out = !oversized; break;
    }
    nanosleep(&interval, NULL); elapsed += 10;
  }
  long out_length, err_length;
  fseek(out, 0, SEEK_END); out_length = ftell(out);
  fseek(err, 0, SEEK_END); err_length = ftell(err);
  if (oversized || out_length < 0 || err_length < 0 || out_length + err_length > 16777216) {
    fclose(out); fclose(err); return process_error("Process output exceeds 16 MiB");
  }
  int code = timed_out ? 124 : WIFEXITED(status) ? WEXITSTATUS(status) : WIFSIGNALED(status) ? 128 + WTERMSIG(status) : -1;
  const char *message = timed_out ? "\nProcess timed out" : "";
  size_t message_length = strlen(message);
  moonbit_bytes_t result = moonbit_make_bytes_raw((int32_t)(8 + out_length + err_length + message_length));
  put_word(result, code); put_word(result + 4, (int)out_length);
  rewind(out); rewind(err);
  fread(result + 8, 1, (size_t)out_length, out);
  fread(result + 8 + out_length, 1, (size_t)err_length, err);
  memcpy(result + 8 + out_length + err_length, message, message_length);
  fclose(out); fclose(err); return result;
#endif
}
