// rusage: run a command and print its wall time, CPU time and peak RSS to stderr as the last line:
//   "rusage wall_ns=<n> cpu_ns=<n> maxrss_kib=<n> status=<exit code>"
// bench/compare/run.py runs each benchmark through it. Why not os.wait4 in Python: Linux keeps the peak
// RSS of the forked parent in the child across exec, so a child of a 25 MB Python reports at least 25 MB.
// This process is small, so the peak RSS of its child is the peak of the benchmark itself.
#include <stdio.h>
#include <sys/resource.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

int main(int argc, char **argv) {
    if (argc < 2) {
        fprintf(stderr, "usage: rusage <command> [args...]\n");
        return 2;
    }
    struct timespec t0, t1;
    clock_gettime(CLOCK_MONOTONIC, &t0);
    pid_t pid = fork();
    if (pid == 0) {
        execvp(argv[1], argv + 1);
        perror("exec");
        _exit(127);
    }
    int status;
    struct rusage ru;
    if (wait4(pid, &status, 0, &ru) < 0) {
        perror("wait4");
        return 2;
    }
    clock_gettime(CLOCK_MONOTONIC, &t1);
    long long wall = (t1.tv_sec - t0.tv_sec) * 1000000000LL + (t1.tv_nsec - t0.tv_nsec);
    long long cpu = (ru.ru_utime.tv_sec + ru.ru_stime.tv_sec) * 1000000000LL +
                    (ru.ru_utime.tv_usec + ru.ru_stime.tv_usec) * 1000LL;
    int code = WIFEXITED(status) ? WEXITSTATUS(status) : 128 + WTERMSIG(status);
    fprintf(stderr, "\nrusage wall_ns=%lld cpu_ns=%lld maxrss_kib=%ld status=%d\n", wall, cpu, ru.ru_maxrss, code);
    return code;
}
