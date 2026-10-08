#include <errno.h>
#include <stdlib.h>
#include <time.h>
int main(int argc, char **argv) {
  double seconds = 0;
  for (int i = 1; i < argc; ++i) {
    char *end;
    double n = strtod(argv[i], &end);
    if (*end || n < 0) return 1;
    seconds += n;
  }
  struct timespec ts = {(time_t)seconds, (long)((seconds - (time_t)seconds) * 1000000000)};
  while (nanosleep(&ts, &ts) && errno == EINTR) {}
  return 0;
}
