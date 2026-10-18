// Host-side sampler for iOS Simulator processes. This file is never linked
// into the application. Report WebKit PIDs separately from the host process.
#include <errno.h>
#include <libproc.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/resource.h>

int main(int argc, char **argv) {
  if (argc < 2) {
    fprintf(stderr, "Usage: process-memory PID [PID ...]\n");
    return 2;
  }
  int failed = 0;
  printf("[");
  for (int index = 1; index < argc; index++) {
    char *end = NULL;
    errno = 0;
    long value = strtol(argv[index], &end, 10);
    if (errno || !end || *end || value < 1 || value > 2147483647L) {
      fprintf(stderr, "Invalid process ID\n");
      return 2;
    }
    int pid = (int)value;
    struct rusage_info_v4 usage = {0};
    struct proc_taskinfo task = {0};
    if (index > 1) printf(",");
    if (proc_pid_rusage(pid, RUSAGE_INFO_V4, (rusage_info_t *)&usage) != 0) {
      printf("{\"pid\":%d,\"errorCode\":%d}", pid, errno);
      failed = 1;
      continue;
    }
    int size = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &task, sizeof(task));
    printf("{\"pid\":%d,\"physicalFootprintBytes\":%llu,\"lifetimePeakPhysicalFootprintBytes\":%llu",
           pid, (unsigned long long)usage.ri_phys_footprint,
           (unsigned long long)usage.ri_lifetime_max_phys_footprint);
    if (size == sizeof(task)) printf(",\"residentBytes\":%llu", (unsigned long long)task.pti_resident_size);
    printf("}");
  }
  printf("]\n");
  return failed;
}
