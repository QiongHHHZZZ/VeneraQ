/* Relocate Debian WebKit's compiled-in helper paths in a private runtime copy.
 * Upstream's WEBKIT_EXEC_PATH override is available only in developer builds.
 * Strings only shrink, preserving every ELF section offset and reference.
 */
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>

static int replace(unsigned char *data, size_t size, const char *old,
                   const char *replacement) {
  size_t old_len = strlen(old), new_len = strlen(replacement);
  int count = 0;
  if (new_len > old_len) return -1;
  for (size_t i = 0; i + old_len < size; ++i) {
    if (memcmp(data + i, old, old_len)) continue;
    unsigned char *end = memchr(data + i + old_len, 0, size - i - old_len);
    if (!end) return -1;
    size_t length = (size_t)(end - data - i);
    /* Preserve suffixes such as /injected-bundle/. */
    memmove(data + i + new_len, data + i + old_len, length - old_len);
    memcpy(data + i, replacement, new_len);
    memset(data + i + length - old_len + new_len, 0, old_len - new_len + 1);
    ++count;
    i += length;
  }
  return count;
}

int main(int argc, char **argv) {
  if (argc != 5) return 2;
  int input = open(argv[1], O_RDONLY);
  struct stat st;
  if (input < 0 || fstat(input, &st) || st.st_size < 4) {
    perror("read WebKit");
    return 1;
  }
  unsigned char *data = mmap(NULL, st.st_size, PROT_READ | PROT_WRITE,
                             MAP_PRIVATE, input, 0);
  close(input);
  if (data == MAP_FAILED) { perror("mmap WebKit"); return 1; }
  const char *old[] = {argv[3], "/usr/bin/bwrap", "/usr/bin/xdg-dbus-proxy"};
  const char *suffix[] = {"/w", "/b", "/d"};
  for (int i = 0; i < 3; ++i) {
    char path[256];
    if (snprintf(path, sizeof(path), "%s%s", argv[4], suffix[i]) >= (int)sizeof(path)
        || replace(data, st.st_size, old[i], path) <= 0) {
      fprintf(stderr, "Unsupported WebKit helper path: %s\n", old[i]);
      return 1;
    }
  }
  int out = open(argv[2], O_WRONLY | O_CREAT | O_EXCL, 0600);
  if (out < 0) { perror("create relocated WebKit"); return 1; }
  size_t offset = 0;
  while (offset < (size_t)st.st_size) {
    ssize_t written = write(out, data + offset, st.st_size - offset);
    if (written < 0 && errno == EINTR) continue;
    if (written <= 0) { perror("write WebKit"); return 1; }
    offset += written;
  }
  if (close(out)) { perror("close WebKit"); return 1; }
  munmap(data, st.st_size);
  return 0;
}
