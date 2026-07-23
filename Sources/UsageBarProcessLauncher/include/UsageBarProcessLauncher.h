#ifndef USAGE_BAR_PROCESS_LAUNCHER_H
#define USAGE_BAR_PROCESS_LAUNCHER_H

#include <sys/types.h>

int usagebar_exec_in_new_process_group(int argc, char *const argv[]);

int usagebar_spawn_in_pty(
    const char *executable,
    char *const argv[],
    char *const envp[],
    const char *working_directory,
    pid_t *pid_out,
    int *master_fd_out
);

#endif
